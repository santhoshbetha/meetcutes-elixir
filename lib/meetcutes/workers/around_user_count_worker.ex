defmodule Meetcutes.Workers.AroundUserCountWorker do
  @moduledoc """
  Refreshes every active user's cached 100-mile opposite-gender match count.

  Scheduled once per day at 03:00 through Oban's Cron plugin. The Oban job is
  unique within an hour so a deploy/manual trigger cannot stampede the queue.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 3_600, fields: [:worker]]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Meetcutes.Matching.refresh_all_around_counts()
    :ok
  end
end
