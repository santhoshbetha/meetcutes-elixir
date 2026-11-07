defmodule MeetcutesWeb.NotificationJSON do
  @moduledoc """
  Serializes inbox items for the notifications API.
  """

  alias Meetcutes.Notifications.Notification

  @doc """
  Returns the client-safe representation of a notification.
  """
  def notification(%Notification{} = notification) do
    %{
      id: notification.id,
      type: Atom.to_string(notification.type),
      title: notification.title,
      body: notification.body,
      is_read: notification.is_read,
      metadata: notification.metadata || %{},
      inserted_at: notification.inserted_at,
      updated_at: notification.updated_at
    }
  end
end
