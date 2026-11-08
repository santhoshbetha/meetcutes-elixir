defmodule MeetcutesWeb.Plugs.HealthCheck do
  @moduledoc """
  Proactive, database-tied health check for orchestration probes.

  The endpoint answers `GET /health` only after two independent checks pass:

    1. `SELECT 1` through the production Ecto pool.
    2. `Ecto.Migrator.migrations/1` reports no pending migrations.

  Any failure returns `503 Service Unavailable` so a load balancer or
  `kamal-proxy` keeps traffic away from an unready container. The plug halts
  for `/health` and is a no-op for every other request.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  @health_path "/health"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{} = conn, opts) do
    if health_path?(conn.request_path) do
      checker = Keyword.get(opts, :check, &__MODULE__.check/0)

      conn
      |> put_resp_content_type("application/json")
      |> respond(checker)
      |> halt()
    else
      conn
    end
  end

  @doc """
  Runs the database and migration checks.

  Returns `:ok` when the container is ready to receive traffic, otherwise an
  error tuple describing the failed tier.
  """
  def check do
    with :ok <- check_database(),
         :ok <- check_migrations() do
      :ok
    end
  end

  @doc """
  Verifies the Postgres pool can execute a lightweight query.
  """
  def check_database do
    case Ecto.Adapters.SQL.query(Meetcutes.Repo, "SELECT 1", []) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, {:database, reason}}
    end
  rescue
    error -> {:error, {:database, error}}
  catch
    kind, reason -> {:error, {:database, {kind, reason}}}
  end

  @doc """
  Verifies the repo has no migrations waiting to run.

  `Ecto.Migrator.migrations/1` returns `{:up, version, name}` for applied
  migrations and `{:down, version, name}` for pending ones.
  """
  def check_migrations do
    case Ecto.Migrator.migrations(Meetcutes.Repo) do
      migrations when is_list(migrations) ->
        case pending(migrations) do
          [] -> :ok
          pending -> {:error, {:pending_migrations, pending}}
        end

      other ->
        {:error, {:migrations, other}}
    end
  rescue
    error -> {:error, {:migrations, error}}
  catch
    kind, reason -> {:error, {:migrations, {kind, reason}}}
  end

  @doc """
  Returns the pending migration tuples from a migrator result.
  """
  def pending(migrations) when is_list(migrations) do
    Enum.filter(migrations, fn
      {:up, _version, _name} -> false
      {_direction, _version, _name} -> true
      _other -> false
    end)
  end

  def pending(_migrations), do: []

  defp respond(conn, checker) do
    case checker.() do
      :ok ->
        send_resp(conn, 200, Jason.encode!(%{status: "healthy"}))

      {:error, reason} ->
        Logger.warning("Health check failed: #{inspect(reason)}")
        send_resp(conn, 503, Jason.encode!(%{status: "unhealthy"}))

      other ->
        Logger.warning("Health check returned an unexpected result: #{inspect(other)}")
        send_resp(conn, 503, Jason.encode!(%{status: "unhealthy"}))
    end
  rescue
    error ->
      Logger.warning("Health check crashed: #{Exception.message(error)}")
      send_resp(conn, 503, Jason.encode!(%{status: "unhealthy"}))
  catch
    kind, reason ->
      Logger.warning("Health check crashed: #{inspect({kind, reason})}")
      send_resp(conn, 503, Jason.encode!(%{status: "unhealthy"}))
  end

  defp health_path?(@health_path), do: true
  defp health_path?(path), do: String.trim_trailing(path, "/") == @health_path
end
