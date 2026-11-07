defmodule MeetcutesWeb.EventChannel do
  use MeetcutesWeb, :channel

  alias Meetcutes.Discussion
  alias Meetcutes.Events
  alias MeetcutesWeb.DiscussionJSON

  @impl true
  def join("event:" <> event_id, _payload, socket) do
    case Events.get_event(event_id) do
      nil ->
        {:error, %{reason: "event_not_found"}}

      _event ->
        Logger.metadata(user_id: socket.assigns.current_user_id)
        {:ok, socket}
    end
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  @impl true
  def handle_in("new_comment", %{"content" => content}, socket) do
    "event:" <> event_id = socket.topic
    user = socket.assigns.current_user

    case Discussion.create_comment(user, event_id, %{"content" => content}) do
      {:ok, comment} ->
        broadcast(socket, "new_comment", %{
          comment: DiscussionJSON.data(comment)
        })

        {:noreply, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: changeset.errors}}, socket}
    end
  end

  @impl true
  def handle_in("join_event", _payload, socket) do
    "event:" <> event_id = socket.topic
    user_id = socket.assigns.current_user_id

    case Events.join_event(event_id, user_id) do
      {:ok, event} ->
        broadcast(socket, "attendees_updated", %{
          event_id: event.id,
          attendees_count: event.attendees_count
        })

        {:noreply, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("leave_event", _payload, socket) do
    "event:" <> event_id = socket.topic
    user_id = socket.assigns.current_user_id

    case Events.leave_event(event_id, user_id) do
      {:ok, event} ->
        broadcast(socket, "attendees_updated", %{
          event_id: event.id,
          attendees_count: event.attendees_count
        })

        {:noreply, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end
end
