defmodule MeetcutesWeb.RelationshipsController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Relationships
  alias MeetcutesWeb.UserJSON

  action_fallback MeetcutesWeb.FallbackController

  @doc """
  GET /api/v1/relationships

  Returns the current user's likes, blocks, mutes, and derived matches.
  """
  def index(conn, _params) do
    user = conn.assigns.current_user

    conn
    |> put_status(:ok)
    |> json(%{status: "success", data: %{relationships: Relationships.summary(user.id)}})
  end

  @doc """
  GET /api/v1/relationships/liked

  Returns the active profiles the bearer user liked within 100 miles.
  """
  def liked(conn, _params), do: proximity_directory(conn, :liked)

  @doc """
  GET /api/v1/relationships/liked-by

  Returns the active profiles who liked the bearer user within 100 miles.
  """
  def liked_by(conn, _params), do: proximity_directory(conn, :liked_by)

  defp proximity_directory(conn, kind) do
    user = conn.assigns.current_user

    entries =
      case kind do
        :liked -> Relationships.list_liked_users(user.id)
        :liked_by -> Relationships.list_liked_by_users(user.id)
      end

    label = if kind == :liked, do: "liked", else: "liked_by"

    users =
      Enum.map(entries, fn %{user: liked_user, distance_miles: distance} ->
        liked_user
        |> UserJSON.public_profile()
        |> Map.put(:distance_miles, distance)
      end)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: %{
        kind: label,
        users: users
      }
    })
  end

  @doc """
  GET /api/v1/relationships/blocked

  Returns the users the bearer user has blocked.
  """
  def blocked(conn, _params), do: directory(conn, :block)

  @doc """
  GET /api/v1/relationships/muted

  Returns the users the bearer user has muted.
  """
  def muted(conn, _params), do: directory(conn, :mute)

  defp directory(conn, kind) do
    user = conn.assigns.current_user

    users =
      case kind do
        :block -> Relationships.list_blocked_users(user.id)
        :mute -> Relationships.list_muted_users(user.id)
      end

    label = if kind == :block, do: "blocked", else: "muted"

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: %{
        kind: label,
        users: Enum.map(users, &UserJSON.public_profile/1)
      }
    })
  end

  @doc """
  POST /api/v1/relationships

  Body: `%{"kind" => "like" | "block" | "mute", "target_id" => "..."}`
  """
  def create(conn, params) do
    actor = conn.assigns.current_user
    kind = params["kind"]
    target_id = params["target_id"] || params["user_id"] || params["targetId"]

    case Relationships.create_relationship(actor.id, target_id, kind) do
      {:ok, relationship} ->
        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          message: "Relationship saved",
          data: %{
            relationship: %{kind: relationship.kind, target_id: relationship.target_id},
            relationships: Relationships.summary(actor.id)
          }
        })

      {:error, reason} ->
        MeetcutesWeb.FallbackController.call(conn, {:error, reason})
    end
  end

  @doc """
  DELETE /api/v1/relationships/:kind/:target_id
  """
  def delete(conn, %{"kind" => kind, "target_id" => target_id}) do
    actor = conn.assigns.current_user

    case Relationships.delete_relationship(actor.id, target_id, kind) do
      {:ok, deleted_kind} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Relationship removed",
          data: %{
            relationship: %{kind: deleted_kind, target_id: target_id},
            relationships: Relationships.summary(actor.id)
          }
        })

      {:error, reason} ->
        MeetcutesWeb.FallbackController.call(conn, {:error, reason})
    end
  end
end
