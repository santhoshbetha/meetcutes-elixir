defmodule Meetcutes.Discussion.Comment do
  use Meetcutes.Schema
  import Ecto.Changeset

  alias Meetcutes.Accounts.User
  alias Meetcutes.Events.Event

  schema "comments" do
    field :content, :string
    belongs_to :user, User
    belongs_to :event, Event

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for comment content.

  `user_id` and `event_id` are deliberately **not** castable: they are set from
  the authenticated session and the URL path in `Meetcutes.Discussion`, never
  from client-supplied attributes.
  """
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:content])
    |> validate_required([:content])
    |> validate_length(:content, min: 1, max: 5_000)
  end
end
