# The Subscription Feed (Option 2)
# This provides a URL that users "Subscribe" to. The calendar app (Google/Apple)
# will poll this URL automatically to find new events.

defmodule MeetcutesWeb.UserCalendarController do
  use MeetcutesWeb, :controller
  alias MeetcutesWeb.CalendarExporter

  def feed(conn, %{"user_token" => token}) do
    user = Meetcutes.Accounts.get_user_by_calendar_token!(token)
    events = Meetcutes.Events.list_upcoming_events_for_user(user)

    # Pass user.time_zone (e.g., "America/New_York") to the exporter
    ics_data = CalendarExporter.to_ics(events, user.time_zone || "UTC")

    conn
    |> put_resp_content_type("text/calendar")
    |> send_resp(200, ics_data)
  end
end
