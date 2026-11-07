defmodule MeetcutesWeb.PaymentController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Billing
  alias Meetcutes.Billing.Invoice
  alias MeetcutesWeb.RawBodyReader

  action_fallback MeetcutesWeb.FallbackController

  @doc """
  POST /api/v1/payments/create-checkout-session

  Creates a hosted Stripe Checkout URL for the authenticated user.
  """
  def create_checkout_session(conn, _params) do
    user = conn.assigns.current_user

    # IO.inspect(user)

    case Billing.create_checkout_session(user) do
      {:ok, %{id: id, url: url}} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: %{
            session_id: id,
            checkout_url: url
          }
        })

      {:error, reason} ->
        # IO.inspect(reason)
        conn
        |> put_status(:bad_gateway)
        |> json(%{
          status: "error",
          message: "Unable to start checkout right now.",
          details: inspect(reason)
        })
    end
  end

  @doc """
  POST /api/v1/payments/create-portal-session

  Returns a Stripe-hosted Billing Portal URL for the authenticated customer.
  """
  def create_portal_session(conn, _params) do
    user = conn.assigns.current_user

    case Billing.create_portal_session(user) do
      {:ok, %{id: id, url: url}} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: %{session_id: id, url: url}
        })

      {:error, :missing_stripe_customer} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          code: "stripe_customer_missing",
          message:
            "No Stripe customer is linked to this account yet. Complete a premium checkout first."
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{
          status: "error",
          message: "Unable to open the billing portal right now.",
          details: inspect(reason)
        })
    end
  end

  @doc """
  POST /api/v1/payments/webhook

  Verifies Stripe's signature against the raw request body, then fulfills the
  completed checkout session.
  """
  def webhook(conn, _params) do
    signature = conn |> get_req_header("stripe-signature") |> List.first()
    payload = RawBodyReader.raw_body(conn)

    cond do
      not is_binary(signature) or signature == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: "Missing Stripe signature"})

      true ->
        handle_verified_webhook(conn, payload, signature)
    end
  end

  defp handle_verified_webhook(conn, payload, signature) do
    case Billing.handle_webhook(payload, signature) do
      {:ok, %Invoice{} = invoice} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", data: %{invoice_id: invoice.id}})

      {:ok, :ignored} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Event ignored"})

      {:error, reason} when is_binary(reason) ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: "Invalid Stripe signature"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          message: "Webhook could not be processed",
          details: inspect(reason)
        })
    end
  end
end
