defmodule Meetcutes.BillingTest do
  use Meetcutes.DataCase, async: false

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts.User
  alias Meetcutes.Billing
  alias Meetcutes.Billing.Invoice
  alias Meetcutes.Repo

  setup do
    user =
      user_fixture(%{email: "billing#{System.unique_integer([:positive])}@example.com"})
      |> Ecto.Changeset.change(%{accepted_onetime_fees_amount: 50})
      |> Repo.update!()

    %{user: user}
  end

  describe "create_checkout_session/1" do
    test "uses the amount accepted at signup and embeds the user id", %{user: user} do
      assert Billing.amount_cents_for(user) == 5_000

      assert {:ok, %{id: id, url: url}} = Billing.create_checkout_session(user)
      assert id =~ "cs_test_"
      assert url =~ "checkout.stripe.test"
      assert url =~ user.id
    end

    test "falls back to the launch price when no accepted amount exists" do
      user =
        user_fixture(%{email: "billingfallback#{System.unique_integer([:positive])}@example.com"})

      assert Billing.amount_cents_for(user) == 5_000
    end
  end

  describe "create_portal_session/1" do
    test "creates a portal session for a user with a Stripe customer", %{user: user} do
      user = Repo.update!(Ecto.Changeset.change(user, %{stripe_customer_id: "cus_test_portal"}))

      assert {:ok, %{id: id, url: url}} = Billing.create_portal_session(user)
      assert id =~ "bps_test_"
      assert url =~ "customer=cus_test_portal"
    end

    test "returns a graceful error when the customer id is missing", %{user: user} do
      user = Repo.update!(Ecto.Changeset.change(user, %{stripe_customer_id: nil}))

      assert {:error, :missing_stripe_customer} = Billing.create_portal_session(user)
    end
  end

  describe "handle_webhook/2" do
    test "creates an invoice, activates the subscription, and stores the PDF", %{user: user} do
      payload = checkout_payload(user, "pi_test_123")

      assert {:ok, %Invoice{} = invoice} = Billing.handle_webhook(payload, "test_signature")

      assert invoice.user_id == user.id
      assert invoice.stripe_charge_id == "pi_test_123"
      assert invoice.amount == 5_000
      assert invoice.receipt_key =~ "invoices/users/#{user.id}/"
      assert invoice.receipt_url =~ "https://cdn.test/"

      updated = Repo.get!(User, user.id)
      assert DateTime.diff(updated.subscription_expires_at, DateTime.utc_now(), :day) >= 364
      assert Billing.subscription_active?(updated)
      assert invoice.period_end == DateTime.add(invoice.period_start, 365, :day)
    end

    test "is idempotent for repeated Stripe deliveries", %{user: user} do
      payload = checkout_payload(user, "pi_test_idempotent")

      assert {:ok, first} = Billing.handle_webhook(payload, "test_signature")
      assert {:ok, second} = Billing.handle_webhook(payload, "test_signature")

      assert first.id == second.id
      assert Repo.aggregate(Invoice, :count, :id) == 1
    end

    test "rejects an invalid signature", %{user: user} do
      payload = checkout_payload(user, "pi_test_bad")

      assert {:error, _reason} = Billing.handle_webhook(payload, "wrong_signature")
      assert Repo.aggregate(Invoice, :count, :id) == 0
    end

    test "ignores unrelated event types", %{user: user} do
      payload =
        Jason.encode!(%{
          "type" => "invoice.paid",
          "data" => %{"object" => %{"id" => "in_test", "customer" => user.id}}
        })

      assert {:ok, :ignored} = Billing.handle_webhook(payload, "test_signature")
    end
  end

  defp checkout_payload(user, charge_id) do
    Jason.encode!(%{
      "type" => "checkout.session.completed",
      "data" => %{
        "object" => %{
          "id" => "cs_test_#{charge_id}",
          "payment_intent" => charge_id,
          "amount_total" => 5_000,
          "customer" => "cus_test_123",
          "client_reference_id" => user.id,
          "metadata" => %{"user_id" => user.id}
        }
      }
    })
  end
end
