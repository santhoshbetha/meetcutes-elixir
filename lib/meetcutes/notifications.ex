defmodule Meetcutes.Notifications do
  @moduledoc """
  Per-user notification inbox.

  Every read and write is scoped to the owning user so one account can never
  inspect or mutate another account's inbox. Reads are intentionally paginated
  and ordered newest-first; unread counts are returned alongside each page so
  navigation badges stay in sync without a second request.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Meetcutes.Notifications.Notification
  alias Meetcutes.Repo
  alias MeetcutesWeb.Endpoint

  @default_per_page 20
  @max_per_page 100

  @doc """
  Returns a page of notifications for `user_id`, newest first.

  The result includes pagination metadata and the user's total unread count.
  """
  def list_notifications(user_id, opts \\ [])

  def list_notifications(user_id, opts) when is_binary(user_id) do
    page = opts |> Keyword.get(:page, 1) |> normalize_positive(1)
    per_page = opts |> Keyword.get(:per_page, @default_per_page) |> normalize_per_page()

    base = from(n in Notification, where: n.user_id == ^user_id)

    total = Repo.aggregate(base, :count, :id)

    notifications =
      base
      |> order_by([n], desc: n.inserted_at, desc: n.id)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Repo.all()

    %{
      notifications: notifications,
      pagination: %{
        page: page,
        per_page: per_page,
        total: total,
        total_pages: total_pages(total, per_page)
      },
      unread_count: unread_count(user_id)
    }
  end

  def list_notifications(_user_id, _opts) do
    %{
      notifications: [],
      pagination: %{page: 1, per_page: @default_per_page, total: 0, total_pages: 0},
      unread_count: 0
    }
  end

  @doc """
  Marks one owned notification as read. Idempotent.
  """
  def mark_read(user_id, id) when is_binary(user_id) and is_binary(id) do
    case Repo.get_by(Notification, id: id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      %Notification{is_read: true} = notification ->
        {:ok, notification}

      %Notification{} = notification ->
        notification
        |> Ecto.Changeset.change(is_read: true)
        |> Repo.update()
    end
  end

  def mark_read(_user_id, _id), do: {:error, :not_found}

  @doc """
  Marks every unread notification owned by `user_id` as read.

  Uses a single SQL update and returns the number of rows touched.
  """
  def mark_all_read(user_id) when is_binary(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {updated, _rows} =
      Repo.update_all(
        from(n in Notification, where: n.user_id == ^user_id and n.is_read == false),
        set: [is_read: true, updated_at: now]
      )

    updated
  end

  def mark_all_read(_user_id), do: 0

  @doc """
  Counts the unread notifications owned by `user_id`.
  """
  def unread_count(user_id) when is_binary(user_id) do
    Repo.aggregate(
      from(n in Notification, where: n.user_id == ^user_id and n.is_read == false),
      :count,
      :id
    )
  end

  def unread_count(_user_id), do: 0

  @doc """
  Creates a notification. Used by other contexts and by tests.

  `attrs` must include `:user_id`; ownership is never taken from request
  parameters by controllers.
  """
  def create_notification(attrs) when is_map(attrs) do
    changeset =
      %Notification{}
      |> Notification.changeset(attrs)
      |> put_user_id(attrs)

    case Repo.insert(changeset) do
      {:ok, notification} ->
        broadcast_created(notification)
        {:ok, notification}

      error ->
        error
    end
  end

  @doc """
  Builds insertable admin-broadcast rows for the MCP notification command.
  """
  def build_admin_broadcasts(user_ids, title, body, metadata \\ %{}) do
    build_broadcasts(user_ids, :admin_broadcast, title, body, metadata)
  end

  @doc """
  Builds insertable event lifecycle rows for every attendee.

  Event rows use the polymorphic `upcoming_event` type so the inbox can render
  its event-specific presentation and deep-link to the event page.
  """
  def build_event_broadcasts(user_ids, title, body, metadata \\ %{}) do
    build_broadcasts(user_ids, :upcoming_event, title, body, metadata)
  end

  defp build_broadcasts(user_ids, type, title, body, metadata) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    user_ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(fn user_id ->
      %{
        id: Ecto.ULID.generate(),
        user_id: user_id,
        type: type,
        title: title,
        body: body,
        is_read: false,
        metadata: metadata || %{},
        inserted_at: now,
        updated_at: now
      }
    end)
  end

  @doc """
  Batch-inserts prepared admin-broadcast rows.
  """
  def insert_broadcast_entries([]), do: 0

  def insert_broadcast_entries(entries) when is_list(entries) do
    {count, _result} = Repo.insert_all(Notification, entries)
    count
  end

  @doc """
  Broadcasts prepared admin-broadcast rows after their transaction commits.
  """
  def broadcast_entries(entries) when is_list(entries),
    do: Enum.each(entries, &broadcast_payload/1)

  @doc """
  Deletes every notification owned by `user_id`.
  """
  def delete_all_for_user(user_id) when is_binary(user_id) do
    Repo.delete_all(from(n in Notification, where: n.user_id == ^user_id))
  end

  # The HTTP write has already committed by the time we get here. A failed
  # broadcast must never turn a successful insert into a request error, so the
  # push is best effort and only logged.
  defp broadcast_created(%Notification{} = notification) do
    broadcast_payload(%{
      id: notification.id,
      user_id: notification.user_id,
      type: Atom.to_string(notification.type),
      title: notification.title,
      body: notification.body,
      is_read: notification.is_read,
      metadata: notification.metadata,
      inserted_at: notification.inserted_at
    })
  end

  defp broadcast_payload(entry) do
    Endpoint.broadcast!(
      "user_notifications:#{entry.user_id}",
      "new_notification",
      %{
        id: entry.id,
        type: notification_type(entry.type),
        title: entry.title,
        body: entry.body,
        is_read: entry.is_read,
        metadata: entry.metadata,
        inserted_at: entry.inserted_at
      }
    )
  rescue
    error ->
      Logger.warning("Unable to broadcast notification #{entry.id}: #{Exception.message(error)}")

      :error
  end

  defp notification_type(type) when is_atom(type), do: Atom.to_string(type)
  defp notification_type(type), do: type

  defp put_user_id(changeset, attrs) do
    case fetch_user_id(attrs) do
      nil -> changeset
      user_id -> Ecto.Changeset.put_change(changeset, :user_id, user_id)
    end
  end

  defp fetch_user_id(attrs) do
    Map.get(attrs, :user_id) || Map.get(attrs, "user_id")
  end

  defp normalize_positive(value, _default) when is_integer(value) and value > 0, do: value

  defp normalize_positive(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp normalize_positive(_value, default), do: default

  defp normalize_per_page(value) do
    value
    |> normalize_positive(@default_per_page)
    |> min(@max_per_page)
  end

  defp total_pages(0, _per_page), do: 0
  defp total_pages(total, per_page), do: div(total + per_page - 1, per_page)
end
