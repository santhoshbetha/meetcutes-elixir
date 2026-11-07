defmodule Meetcutes.Billing.StripeClient.Live do
  @moduledoc """
  Real Stripe integration backed by `stripity_stripe`.
  """

  @behaviour Meetcutes.Billing.StripeClient

  @impl true
  def create_checkout_session(params) do
    case Stripe.Checkout.Session.create(params) do
      {:ok, %{id: id, url: url}} when is_binary(url) ->
        {:ok, %{id: id, url: url}}

      {:ok, %{id: id}} ->
        {:error, {:missing_checkout_url, id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def create_portal_session(params) do
    case Stripe.BillingPortal.Session.create(params) do
      {:ok, %{id: id, url: url}} when is_binary(url) ->
        {:ok, %{id: id, url: url}}

      {:ok, %{id: id}} ->
        {:error, {:missing_portal_url, id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def construct_event(payload, signature) do
    with secret when is_binary(secret) and secret != "" <- webhook_secret() do
      Stripe.Webhook.construct_event(payload, signature, secret, response_as: :map)
    else
      _ -> {:error, :missing_webhook_secret}
    end
  end

  defp webhook_secret do
    :meetcutes
    |> Application.get_env(:stripe, [])
    |> Keyword.get(:webhook_secret)
  end
end
