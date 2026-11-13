defmodule Meetcutes.Uploads.PhotoHash do
  @moduledoc """
  A content-hash claim for an uploaded photo.

  Rows are created and removed only by the photo upload/delete pipeline. The
  hash is used to prevent a different account from claiming identical image
  bytes while still allowing the same account to reuse its own image.
  """

  use Meetcutes.Schema
  import Ecto.Changeset

  alias Meetcutes.Accounts.User

  schema "photo_hashes" do
    field :hash, :string
    field :filename, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(photo_hash \\ %__MODULE__{}, attrs) do
    photo_hash
    |> cast(attrs, [:hash, :filename, :user_id])
    |> validate_required([:hash, :filename, :user_id])
    |> validate_length(:hash, is: 64)
  end
end
