defmodule MeetcutesWeb.JobUpdateChannel do
  use MeetcutesWeb, :channel

  @impl true
  def join("job_updates:" <> user_id, _payload, socket) do
    # Verify that the user_id in the topic matches the authenticated user
    if socket.assigns.current_user.id == user_id do
      Logger.metadata(user_id: user_id)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  @doc """
  Broadcasts a job update to the user's job_updates channel.

  ## Parameters
  - user_id: The ID of the user to notify
  - job_id: The ID of the job being updated
  - status: The status of the job (e.g., "processing", "completed", "failed")
  - data: Optional additional data (defaults to empty map)
  """
  def broadcast_job_update(user_id, job_id, status, data \\ %{}) do
    payload = %{
      job_id: job_id,
      status: status,
      data: data,
      timestamp: DateTime.utc_now()
    }

    MeetcutesWeb.Endpoint.broadcast("job_updates:#{user_id}", "job_update", payload)
  end
end
