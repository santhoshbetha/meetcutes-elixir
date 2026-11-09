defmodule MeetcutesWeb.HealthController do
  use MeetcutesWeb, :controller
  import Ecto.Query
  alias Meetcutes.Repo

  @doc """
  Responds with an HTTP 200 if the app and its dependencies are running flawlessly.
  Returns an HTTP 503 if any core subsystem (DB or Oban) goes down.
  """
  def show(conn, _params) do
    # 1. Check Database connection pool vitality
    db_status = check_database()

    # 2. Check Oban Engine queue status
    oban_status = check_oban()

    # 3. Formulate the overarching system health metric
    if db_status == :up and oban_status.engine == "up" do
      conn
      # HTTP 200
      |> put_status(:ok)
      |> json(%{
        status: "healthy",
        timestamp: DateTime.utc_now() |> DateTime.to_string(),
        services: %{
          database: "up",
          oban_background_workers: oban_status
        }
      })
    else
      conn
      # HTTP 503
      |> put_status(:service_unavailable)
      |> json(%{
        status: "unhealthy",
        timestamp: DateTime.utc_now() |> DateTime.to_string(),
        services: %{
          database: to_string(db_status),
          oban_background_workers: oban_status
        }
      })
    end
  end

  # --- Private Subsystem Checkers ---

  defp check_database do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} -> :up
      {:error, _reason} -> :down
    end
  end

  defp check_oban do
    try do
      config = Oban.config()
      active_queues = config.queues |> Keyword.keys()

      # Fix: Convert the Postgres Enum column to plain text inside a fragment
      # so it can be compared to our plain string parameter safely.
      target_state = "failed"

      failed_jobs_count =
        Repo.one(
          from(j in "oban_jobs",
            where: fragment("?::text = ?", j.state, ^target_state),
            select: count(j.id)
          )
        ) || 0

      %{
        engine: "up",
        active_queues: active_queues,
        failed_jobs_backlog: failed_jobs_count
      }
    rescue
      _exception ->
        # Wiped out the IO.inspect logging since the fragment format resolves the error
        # IO.inspect(exception, label: "CRITICAL HEALTH CHECK OBAN EXCEPTION")
        %{engine: "down", active_queues: [], failed_jobs_backlog: 0}
    end
  end
end
