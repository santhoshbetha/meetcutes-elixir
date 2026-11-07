defmodule MeetcutesWeb.NotificationsController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Notifications
  alias MeetcutesWeb.NotificationJSON

  action_fallback MeetcutesWeb.FallbackController

  @default_per_page 20
  @max_per_page 100

  @doc """
  GET /api/v1/notifications

  Returns the authenticated user's inbox page, newest first. Accepts `page`
  and `per_page` query parameters.
  """
  def index(conn, params) do
    user = conn.assigns.current_user
    page = positive_integer(params["page"], 1)
    per_page = params["per_page"] |> positive_integer(@default_per_page) |> min(@max_per_page)

    result = Notifications.list_notifications(user.id, page: page, per_page: per_page)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: %{
        notifications: Enum.map(result.notifications, &NotificationJSON.notification/1),
        pagination: result.pagination,
        unread_count: result.unread_count
      }
    })
  end

  @doc """
  PATCH /api/v1/notifications/:id/read

  Marks a single notification owned by the bearer user as read.
  """
  def read(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Notifications.mark_read(user.id, id) do
      {:ok, notification} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: %{
            notification: NotificationJSON.notification(notification),
            unread_count: Notifications.unread_count(user.id)
          }
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          status: "error",
          code: "notification_not_found",
          message: "Notification not found"
        })
    end
  end

  @doc """
  POST /api/v1/notifications/mark-all-read

  Bulk-marks every unread notification owned by the bearer user as read.
  """
  def mark_all_read(conn, _params) do
    user = conn.assigns.current_user
    updated = Notifications.mark_all_read(user.id)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      message: "All notifications marked as read",
      data: %{updated: updated, unread_count: 0}
    })
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp positive_integer(_value, default), do: default
end
