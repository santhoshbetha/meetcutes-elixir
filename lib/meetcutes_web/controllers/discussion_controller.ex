defmodule MeetcutesWeb.DiscussionController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Discussion
  alias Meetcutes.Events
  alias MeetcutesWeb.DiscussionJSON

  action_fallback MeetcutesWeb.FallbackController

  # GET /events/:event_id/comments
  def index(conn, %{"event_id" => event_id}) do
    with {:ok, _event} <- fetch_event(event_id) do
      comments = Discussion.list_comments(event_id)
      json(conn, DiscussionJSON.index(%{comments: comments}))
    end
  end

  # POST /events/:event_id/comments
  def create(conn, %{"event_id" => event_id} = params) do
    attrs = Map.get(params, "comment", %{})

    with {:ok, _event} <- fetch_event(event_id),
         {:ok, comment} <-
           Discussion.create_comment(conn.assigns.current_user, event_id, attrs) do
      MeetcutesWeb.Endpoint.broadcast("comments:#{event_id}", "new_comment", %{
        comment: DiscussionJSON.data(comment)
      })

      MeetcutesWeb.Endpoint.broadcast(
        "events:discussion:#{event_id}",
        "new_comment",
        %{comment: DiscussionJSON.data(comment)}
      )

      conn
      |> put_status(:created)
      |> json(DiscussionJSON.show(%{comment: comment}))
    end
  end

  # PUT /comments/:id
  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "comment", %{})

    with {:ok, comment} <- fetch_comment(id),
         {:ok, updated} <-
           Discussion.update_comment(comment, conn.assigns.current_user, attrs) do
      MeetcutesWeb.Endpoint.broadcast(
        "comments:#{updated.event_id}",
        "comment_updated",
        %{comment: DiscussionJSON.data(updated)}
      )

      MeetcutesWeb.Endpoint.broadcast(
        "events:discussion:#{updated.event_id}",
        "comment_updated",
        %{comment: DiscussionJSON.data(updated)}
      )

      json(conn, DiscussionJSON.show(%{comment: updated}))
    end
  end

  # DELETE /comments/:id
  def delete(conn, %{"id" => id}) do
    with {:ok, comment} <- fetch_comment(id),
         {:ok, _deleted} <-
           Discussion.delete_comment(comment, conn.assigns.current_user) do
      MeetcutesWeb.Endpoint.broadcast("comments:#{comment.event_id}", "comment_deleted", %{
        comment_id: comment.id
      })

      MeetcutesWeb.Endpoint.broadcast(
        "events:discussion:#{comment.event_id}",
        "comment_deleted",
        %{comment_id: comment.id}
      )

      send_resp(conn, :no_content, "")
    end
  end

  defp fetch_event(event_id) do
    case Events.get_event(event_id) do
      nil -> {:error, :event_not_found}
      event -> {:ok, event}
    end
  end

  defp fetch_comment(id) do
    case Discussion.get_comment(id) do
      nil -> {:error, :not_found}
      comment -> {:ok, comment}
    end
  end
end
