defmodule Meetcutes.Workers.CleanupOldEvents do
  @moduledoc """
  Worker that deletes events older than a month and cleans up images of soft-deleted users.
  Runs daily at 2 AM.
  """

  use Oban.Worker, queue: :events, max_attempts: 3

  alias Meetcutes.Events
  alias Meetcutes.Accounts

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Clean up old events
    events_result = Events.delete_old_events()

    # Clean up images of soft-deleted users (older than 30 days)
    images_result = Accounts.delete_soft_deleted_users_images()

    # Log results
    require Logger

    case events_result do
      {:ok, events_count, comments_deleted} ->
        Logger.info(
          "Successfully deleted #{events_count} old events and #{comments_deleted} related comments"
        )

      {:error, reason} ->
        Logger.error("Failed to delete old events: #{inspect(reason)}")
    end

    case images_result do
      {:ok, users_count} ->
        Logger.info("Successfully cleaned up images for #{users_count} soft-deleted users")

      {:error, reason} ->
        Logger.error("Failed to cleanup soft-deleted user images: #{inspect(reason)}")
    end

    # Return error if either operation failed
    case {events_result, images_result} do
      {{:error, _}, _} -> {:error, "Events cleanup failed"}
      {_, {:error, _}} -> {:error, "Images cleanup failed"}
      _ -> :ok
    end
  end
end
