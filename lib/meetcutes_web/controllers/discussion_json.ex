defmodule MeetcutesWeb.DiscussionJSON do
  alias Meetcutes.Accounts.User
  alias Meetcutes.Discussion.Comment
  alias Meetcutes.Uploads

  @doc """
  Renders a list of comments.
  """
  def index(%{comments: comments}) do
    %{data: for(comment <- comments, do: data(comment))}
  end

  @doc """
  Renders a single comment.
  """
  def show(%{comment: comment}) do
    %{data: data(comment)}
  end

  def data(%Comment{} = comment) do
    user = comment.user

    %{
      id: comment.id,
      content: comment.content,
      user_id: comment.user_id,
      event_id: comment.event_id,
      user: %{
        id: user.id,
        nickname: user.nickname,
        handle: user.nickname,
        first_name: user.first_name,
        last_name: user.last_name,
        avatar: user.avatar,
        avatar_url: avatar_url(user)
      },
      inserted_at: comment.inserted_at,
      updated_at: comment.updated_at
    }
  end

  defp avatar_url(%User{} = user) do
    case user.avatar do
      %{"url" => url} when is_binary(url) -> url
      %{url: url} when is_binary(url) -> url
      %{"filename" => filename} when is_binary(filename) -> storage_url(user, filename)
      %{filename: filename} when is_binary(filename) -> storage_url(user, filename)
      filename when is_binary(filename) -> storage_url(user, filename)
      _other -> nil
    end
  end

  defp storage_url(user, filename) do
    Uploads.url(user, filename)
  rescue
    _ -> nil
  end
end
