defmodule MeetcutesWeb.JobController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Repo
  alias Oban.Job

  action_fallback MeetcutesWeb.FallbackController

  def status(conn, %{"id" => job_id}) do
    user = conn.assigns.current_user

    case Repo.get(Job, job_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{
          status: "error",
          message: "Resource lookup failed",
          errors: ["Job not found"]
        })

      job ->
        # Check if the job belongs to the current user (by checking args)
        if job.args["user_id"] == user.id do
          conn
          |> put_status(:ok)
          |> json(%{status: "success", data: %{job: job}})
        else
          conn
          |> put_status(:forbidden)
          |> json(%{status: "error", message: "Access denied"})
        end
    end
  end
end
