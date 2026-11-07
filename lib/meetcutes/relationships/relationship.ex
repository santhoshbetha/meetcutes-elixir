defmodule Meetcutes.Relationships.Relationship do
  @moduledoc """
  A directed relationship between two users.

  `kind` is one of `:like`, `:block`, or `:mute`. Matches are derived from
  mutual likes rather than stored as their own row so the two sides of a
  connection can never drift out of sync.
  """

  use Meetcutes.Schema

  alias Meetcutes.Accounts.User

  schema "relationships" do
    field :kind, Ecto.Enum, values: [:like, :block, :mute]

    belongs_to :actor, User
    belongs_to :target, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a relationship changeset.

  Actor and target are set programmatically by the context, never cast from
  client params, so a caller cannot spoof either side of the relationship.
  """
  def changeset(relationship \\ %__MODULE__{}, attrs) do
    relationship
    |> Ecto.Changeset.change(attrs)
    |> Ecto.Changeset.validate_required([:actor_id, :target_id, :kind])
    |> Ecto.Changeset.unique_constraint([:actor_id, :target_id, :kind])
  end
end
