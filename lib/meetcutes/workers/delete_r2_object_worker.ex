defmodule Meetcutes.Workers.DeleteR2ObjectWorker do
  @moduledoc """
  Deletes a replaced or removed avatar/gallery object outside the request path.

  The file metadata is already committed or removed before this job runs, so a
  transient R2/S3 failure only affects orphaned bytes. Oban retries five times
  with its default backoff.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias Meetcutes.Accounts.User
  alias Meetcutes.Uploads

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "filename" => filename}})
      when is_binary(user_id) and is_binary(filename) and filename != "" do
    user = %User{id: user_id}

    case Uploads.storage().delete(user, filename) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _other -> :ok
    end
  end

  def perform(_job), do: :ok
end
