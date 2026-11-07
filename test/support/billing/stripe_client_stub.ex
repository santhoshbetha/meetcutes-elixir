defmodule Meetcutes.Billing.StripeClientStub do
  @moduledoc """
  Deterministic Stripe boundary for the test suite.

  Checkout URLs never leave the machine and webhook payloads are only accepted
  when they carry the test signature header.
  """

  @behaviour Meetcutes.Billing.StripeClient

  @impl true
  def create_checkout_session(params) do
    user_id =
      get_in(params, [:client_reference_id]) ||
        get_in(params, [:metadata, :user_id]) ||
        get_in(params, ["client_reference_id"])

    id = "cs_test_#{System.unique_integer([:positive])}"

    {:ok,
     %{
       id: id,
       url: "https://checkout.stripe.test/#{id}?user=#{user_id}"
     }}
  end

  @impl true
  def create_portal_session(params) do
    customer =
      Map.get(params, :customer) ||
        Map.get(params, "customer")

    id = "bps_test_#{System.unique_integer([:positive])}"

    {:ok,
     %{
       id: id,
       url: "https://billing.stripe.test/#{id}?customer=#{customer}"
     }}
  end

  @impl true
  def construct_event(payload, "test_signature") do
    case Jason.decode(payload) do
      {:ok, event} -> {:ok, event}
      {:error, _reason} -> {:error, "invalid payload"}
    end
  end

  def construct_event(_payload, _signature), do: {:error, "invalid signature"}
end
