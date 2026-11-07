defmodule Meetcutes.Notifications.Notification do
  @moduledoc """
  A single inbox item owned by one user.

  `type` selects the presentation the client should render. `metadata` carries
  the type-specific pointers (for example an event id or the sender of a like)
  so the inbox can deep-link without a schema change per notification kind.
  """

  use Meetcutes.Schema
  import Ecto.Changeset

  alias Meetcutes.Accounts.User

  @types [:upcoming_event, :profile_like, :admin_broadcast]

  schema "notifications" do
    field :type, Ecto.Enum, values: @types
    field :title, :string
    field :body, :string
    field :is_read, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the notification types the inbox understands.
  """
  def types, do: @types

  @doc """
  Builds a notification changeset.

  Ownership is assigned by the context through `user_id`, never accepted from
  an HTTP payload.
  """
  def changeset(notification \\ %__MODULE__{}, attrs) do
    notification
    |> cast(attrs, [:type, :title, :body, :is_read, :metadata])
    |> validate_required([:type, :title])
    |> validate_length(:title, max: 200)
    |> validate_length(:body, max: 5_000)
    |> foreign_key_constraint(:user_id)
  end
end
