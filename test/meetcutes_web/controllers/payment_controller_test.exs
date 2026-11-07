defmodule MeetcutesWeb.PaymentControllerTest do
  use MeetcutesWeb.ConnCase, async: false

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Billing.Invoice
  alias Meetcutes.Repo

  setup %{conn: conn} do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)
    conn = put_req_header(conn, "authorization", "Bearer " <> token)

    %{conn: conn, user: user, token: token}
  end

  describe "POST /api/v1/payments/create-checkout-session" do
    test "returns a hosted checkout URL for the bearer user", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/payments/create-checkout-session")

      assert %{
               "status" => "success",
               "data" => %{"session_id" => id, "checkout_url" => url}
             } = json_response(conn, 200)

      assert id =~ "cs_test_"
      assert url =~ "checkout.stripe.test"
    end

    test "requires authentication" do
      conn = build_conn() |> post(~p"/api/v1/payments/create-checkout-session")

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/v1/payments/create-portal-session" do
    test "returns a hosted billing portal URL", %{conn: conn, user: user} do
      _user =
        Repo.update!(Ecto.Changeset.change(user, %{stripe_customer_id: "cus_test_portal"}))

      conn = post(conn, ~p"/api/v1/payments/create-portal-session")

      assert %{
               "status" => "success",
               "data" => %{"session_id" => id, "url" => url}
             } = json_response(conn, 200)

      assert id =~ "bps_test_"
      assert url =~ "customer=cus_test_portal"
    end

    test "returns a graceful payload when no Stripe customer is linked", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/payments/create-portal-session")

      assert %{
               "status" => "error",
               "code" => "stripe_customer_missing"
             } = json_response(conn, 422)
    end

    test "requires authentication" do
      conn = build_conn() |> post(~p"/api/v1/payments/create-portal-session")

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/v1/payments/webhook" do
    test "fulfills a signed checkout session", %{user: user} do
      payload =
        Jason.encode!(%{
          "type" => "checkout.session.completed",
          "data" => %{
            "object" => %{
              "id" => "cs_test_controller",
              "payment_intent" => "pi_test_controller",
              "amount_total" => 5_000,
              "client_reference_id" => user.id,
              "metadata" => %{"user_id" => user.id}
            }
          }
        })

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", "test_signature")
        |> post(~p"/api/v1/payments/webhook", payload)

      assert %{"status" => "success", "data" => %{"invoice_id" => invoice_id}} =
               json_response(conn, 200)

      assert Repo.get!(Invoice, invoice_id).user_id == user.id
    end

    test "rejects a missing signature" do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/v1/payments/webhook",
          Jason.encode!(%{"type" => "checkout.session.completed"})
        )

      assert %{"status" => "error"} = json_response(conn, 400)
    end

    test "rejects a bad signature" do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", "wrong")
        |> post(
          ~p"/api/v1/payments/webhook",
          Jason.encode!(%{"type" => "checkout.session.completed"})
        )

      assert %{"status" => "error"} = json_response(conn, 400)
    end
  end
end
