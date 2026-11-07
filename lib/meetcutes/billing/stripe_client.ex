defmodule Meetcutes.Billing.StripeClient do
  @moduledoc """
  Boundary between the billing context and Stripe.

  A behaviour keeps checkout creation and webhook verification mockable in
  tests without ever making an outbound Stripe request from the suite.
  """

  @callback create_checkout_session(map()) ::
              {:ok, %{id: String.t(), url: String.t()}} | {:error, term()}

  @callback create_portal_session(map()) ::
              {:ok, %{id: String.t(), url: String.t()}} | {:error, term()}

  @callback construct_event(binary(), binary()) :: {:ok, map()} | {:error, term()}
end
