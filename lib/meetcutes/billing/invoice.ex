defmodule Meetcutes.Billing.Invoice do
  @moduledoc """
  A completed annual membership purchase.

  `stripe_charge_id` is unique so Stripe webhook retries stay idempotent. The
  receipt key/url point at the archived PDF in R2.
  """

  use Meetcutes.Schema
  import Ecto.Changeset

  alias Meetcutes.Accounts.User

  schema "invoices" do
    field :stripe_charge_id, :string
    field :amount, :integer, default: 5000
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime
    field :receipt_key, :string
    field :receipt_url, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds an invoice changeset. Ownership and Stripe identifiers are set by the
  billing context, never cast from client input.
  """
  def changeset(invoice \\ %__MODULE__{}, attrs) do
    invoice
    |> cast(attrs, [
      :stripe_charge_id,
      :amount,
      :period_start,
      :period_end,
      :receipt_key,
      :receipt_url
    ])
    |> validate_required([:stripe_charge_id, :amount, :period_start, :period_end])
    |> validate_number(:amount, greater_than: 0)
    |> unique_constraint(:stripe_charge_id)
    |> foreign_key_constraint(:user_id)
  end
end
