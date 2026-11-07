defmodule Meetcutes.Billing.Receipt do
  @moduledoc """
  Plain-text receipt copy used in both the PDF and the transactional email.
  """

  alias Meetcutes.Accounts.User
  alias Meetcutes.Billing.Invoice

  def render(%Invoice{} = invoice, %User{} = user) do
    """
    MeetCutes Premium Membership
    ============================

    Member: #{display_name(user)}
    Email: #{user.email}
    Invoice: #{invoice.id}
    Stripe charge: #{invoice.stripe_charge_id}
    Amount: $#{format_amount(invoice.amount)}
    Membership period: #{format_date(invoice.period_start)} - #{format_date(invoice.period_end)}

    This receipt confirms a one-year premium membership. Your subscription
    unlocks unlimited discovery and event search until #{format_date(invoice.period_end)}.

    Questions? Contact hello@meetcutes.us.
    """
  end

  defp display_name(%User{} = user) do
    [user.first_name, user.last_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> user.nickname || user.email
      name -> name
    end
  end

  defp format_amount(amount) when is_integer(amount),
    do: :erlang.float_to_binary(amount / 100, decimals: 2)

  defp format_amount(_amount), do: "50.00"

  defp format_date(%DateTime{} = value), do: DateTime.to_date(value) |> Date.to_iso8601()

  defp format_date(%NaiveDateTime{} = value),
    do: NaiveDateTime.to_date(value) |> Date.to_iso8601()

  defp format_date(_value), do: "N/A"
end
