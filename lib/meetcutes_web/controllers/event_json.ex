defmodule MeetcutesWeb.EventJSON do
  alias Meetcutes.Accounts
  alias Meetcutes.Events.{Event, Location}

  @doc """
  Renders a list of events.
  """
  def index(%{events: events, pagination: pagination}) do
    counts = Meetcutes.Events.gender_counts(Enum.map(events, & &1.id))

    %{
      events:
        Enum.map(
          events,
          &event_data(&1, [], Map.get(counts, &1.id, %{}))
        ),
      pagination: pagination
    }
  end

  @doc """
  Renders a single event.
  """
  def show(%{event: event}) do
    counts = Meetcutes.Events.gender_counts([event.id]) |> Map.get(event.id, %{})
    %{event: event_data(event, [], counts)}
  end

  @doc """
  Renders one event without wrapping it in an `event` key.

  `blocked_ids` lets the viewer-scoped API hide blocked attendees while the
  legacy/channel call sites keep their existing behaviour. `counts` carries the
  pre-aggregated demographic totals from the Events context.
  """
  def event(%Event{} = event, blocked_ids \\ [], counts \\ %{}) do
    event_data(event, blocked_ids, counts)
  end

  defp event_data(%Event{} = event, blocked_ids, counts) do
    attendees = attendee_data(event, blocked_ids)

    %{
      id: event.id,
      title: event.title,
      content: event.content,
      start_at: event.start_at,
      end_at: event.end_at,
      event_date: event.event_date,
      status: event.status,
      has_age_restriction: event.has_age_restriction,
      men_min_age: event.men_min_age,
      men_max_age: event.men_max_age,
      women_min_age: event.women_min_age,
      women_max_age: event.women_max_age,
      location: location_data(event.location),
      attendees_count: length(attendees),
      male_count: Map.get(counts, :male_count, event.male_count || 0),
      female_count: Map.get(counts, :female_count, event.female_count || 0),
      attendees: attendees,
      internal_notes: event.internal_notes,
      created_by: event.created_by,
      updated_at: event.updated_at,
      inserted_at: event.inserted_at
    }
  end

  # Attendee snapshots are written at join time. Falling back to the user table
  # keeps events created before the snapshot existed renderable. Blocked users
  # are removed from the viewer's attendee projection.
  defp attendee_data(%Event{} = event, blocked_ids) do
    attendees = event.attendees || %{}
    blocked = MapSet.new(blocked_ids)
    ids = Map.keys(attendees)
    users = Accounts.list_users_by_ids(ids) |> Map.new(&{&1.id, &1})

    attendees
    |> Enum.reject(fn {user_id, _snapshot} -> MapSet.member?(blocked, user_id) end)
    |> Enum.map(fn {user_id, snapshot} ->
      snapshot = snapshot || %{}
      user = Map.get(users, user_id)

      %{
        id: user_id,
        handle: snapshot["handle"] || (user && user.nickname),
        gender: snapshot["gender"] || (user && user.gender),
        first_name: snapshot["first_name"] || (user && user.first_name),
        last_name: snapshot["last_name"] || (user && user.last_name)
      }
    end)
    |> Enum.sort_by(& &1.handle)
  end

  defp location_data(%Location{} = location) do
    %{
      id: location.id,
      name: location.name,
      url: location.url,
      longitude: location.longitude,
      latitude: location.latitude,
      street: location.street,
      postal_code: location.postal_code,
      locality: location.locality,
      region: location.region,
      state: location.state,
      country: location.country
    }
  end

  defp location_data(_), do: %{}
end
