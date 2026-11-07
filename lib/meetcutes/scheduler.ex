defmodule Meetcutes.Scheduler do
  @moduledoc """
  Scheduler that runs recurring jobs at specified intervals.
  Currently schedules the CleanupOldEvents job to run daily at midnight.
  """

  use GenServer

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  @impl true
  def init(state) do
    # Schedule the first cleanup job
    schedule_next_cleanup()
    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup_old_events, state) do
    Logger.info("Starting scheduled cleanup of old events")

    # Enqueue the cleanup job
    case Oban.insert(Meetcutes.Workers.CleanupOldEvents.new(%{})) do
      {:ok, job} ->
        Logger.info("Enqueued cleanup job with ID: #{job.id}")

      {:error, error} ->
        Logger.error("Failed to enqueue cleanup job: #{inspect(error)}")
    end

    # Schedule the next cleanup
    schedule_next_cleanup()

    {:noreply, state}
  end

  defp schedule_next_cleanup do
    # Calculate milliseconds until next midnight
    now = DateTime.utc_now()
    tomorrow = DateTime.add(now, 1, :day)
    midnight = %{tomorrow | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

    # If we already passed midnight today, schedule for tomorrow
    next_midnight =
      if DateTime.compare(now, midnight) == :lt do
        midnight
      else
        DateTime.add(midnight, 1, :day)
      end

    milliseconds_until_midnight = DateTime.diff(next_midnight, now, :millisecond)

    # Schedule the job
    Process.send_after(self(), :cleanup_old_events, milliseconds_until_midnight)

    Logger.info(
      "Next cleanup scheduled for #{DateTime.to_string(next_midnight)} (in #{milliseconds_until_midnight}ms)"
    )
  end
end
