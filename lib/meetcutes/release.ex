defmodule Meetcutes.Release do
  @moduledoc """
  Release tasks that run inside the production container.

  The boot overlay calls `Meetcutes.Release.migrate/0` before the endpoint
  starts, so a freshly built image always brings the database schema up to date
  before `kamal-proxy` routes live traffic to it.
  """

  @app :meetcutes

  @doc """
  Runs every pending migration for each configured repo.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _repo, _migrations} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  # Exposes seed file evaluation inside the production environment context
  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          # Evaluates your data seeds script over the active repo connection pool
          Code.eval_file(Application.app_dir(@app, "priv/repo/seeds.exs"))
        end)
    end
  end

  @doc """
  Rolls a repo back to a specific migration version.
  """
  def rollback(repo, version) do
    load_app()

    {:ok, _repo, _migrations} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Loading (not starting) the application makes the compiled app's
    # configuration available without booting the endpoint or Oban.
    Application.load(@app)
  end
end
