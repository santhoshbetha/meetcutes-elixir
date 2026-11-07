defmodule MeetcutesWeb.CalendarExporter do
  alias ICalendar.Event

  def to_ics(events, timezone \\ "UTC") do
    events
    |> Enum.map(fn event -> build_event(event, timezone) end)
    |> then(&%ICalendar{events: [&1]})
    |> ICalendar.to_ics()
  end

  defp build_event(event, timezone) do
    # Convert UTC to User's Timezone using the Tz library
    start_time = shift_to_zone(event.start_time, timezone)
    end_time = shift_to_zone(event.end_time, timezone)

    %Event{
      summary: event.title,
      dtstart: start_time,
      dtend: end_time,
      description: event.description,
      location: event.location
    }
  end

  defp shift_to_zone(datetime, timezone) do
    case DateTime.shift_zone(datetime, timezone, Tz.TimeZoneDatabase) do
      {:ok, shifted} -> shifted
      # Fallback to UTC if timezone is invalid
      _ -> datetime
    end
  end
end
