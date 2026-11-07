defmodule Meetcutes.Discussion do
  @moduledoc """
  The Discussion context.

  Comment ownership is enforced here rather than in the controller so every
  caller (HTTP API, Phoenix channels) shares the same rules. The author and
  event are always derived from trusted inputs and can never be overridden by
  request attributes.
  """

  import Ecto.Query, warn: false

  alias Meetcutes.Accounts.User
  alias Meetcutes.Discussion.Comment
  alias Meetcutes.Repo

  @doc """
  Returns the list of comments for an event, newest first.
  """
  def list_comments(event_id) do
    Comment
    |> where([c], c.event_id == ^event_id)
    |> order_by([c], desc: c.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Gets a single comment with its author preloaded.

  Returns `nil` when the comment does not exist.
  """
  def get_comment(id) do
    case Repo.get(Comment, id) do
      nil -> nil
      comment -> Repo.preload(comment, :user)
    end
  end

  @doc """
  Creates a comment authored by `author` on `event_id`.

  The client only supplies `:content`; the author id and event id are taken
  from the arguments and written explicitly on the struct.
  """
  def create_comment(%User{} = author, event_id, attrs) when is_binary(event_id) do
    %Comment{user_id: author.id, event_id: event_id}
    |> Comment.changeset(attrs)
    |> Repo.insert()
    |> preload_author()
  end

  @doc """
  Updates a comment's content.

  Returns `{:error, :not_comment_owner}` when `actor` is not the author.
  """
  def update_comment(%Comment{} = comment, %User{} = actor, attrs) do
    with :ok <- authorize_owner(comment, actor) do
      comment
      |> Comment.changeset(attrs)
      |> Repo.update()
      |> preload_author()
    end
  end

  @doc """
  Deletes a comment.

  Returns `{:error, :not_comment_owner}` when `actor` is not the author.
  """
  def delete_comment(%Comment{} = comment, %User{} = actor) do
    with :ok <- authorize_owner(comment, actor) do
      Repo.delete(comment)
    end
  end

  @doc """
  Deletes all comments for a given event.
  """
  def delete_comments_by_event_id(event_id) do
    Comment
    |> where([c], c.event_id == ^event_id)
    |> Repo.delete_all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking comment changes.
  """
  def change_comment(%Comment{} = comment, attrs \\ %{}) do
    Comment.changeset(comment, attrs)
  end

  defp authorize_owner(%Comment{user_id: user_id}, %User{id: user_id}), do: :ok

  defp authorize_owner(%Comment{}, %User{}), do: {:error, :not_comment_owner}

  defp preload_author({:ok, %Comment{} = comment}),
    do: {:ok, Repo.preload(comment, :user)}

  defp preload_author(other), do: other
end
