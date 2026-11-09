# Prints recent Oban jobs as JSON for the Playwright transactional mail specs.
#
# Run from meetcutes-elixir with:
#
#     OBAN_WORKER=Meetcutes.Workers.NotificationWorker \
#       mix run --no-start priv/e2e/inspect_oban.exs
#
# `--no-start` avoids binding the API port while the Playwright webServer is
# already running. Only the Postgres-backed Repo is started.

import Ecto.Query

{:ok, _} = Application.ensure_all_started(:ssl)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Meetcutes.Repo.start_link()

worker = System.get_env("OBAN_WORKER") || "Meetcutes.Workers.NotificationWorker"
limit = String.to_integer(System.get_env("OBAN_LIMIT") || "20")

jobs =
  Meetcutes.Repo.all(
    from j in Oban.Job,
      where: j.worker == ^worker,
      order_by: [desc: j.inserted_at],
      limit: ^limit,
      select: %{
        id: j.id,
        state: j.state,
        queue: j.queue,
        args: j.args,
        inserted_at: j.inserted_at
      }
  )

IO.puts(Jason.encode!(jobs))
