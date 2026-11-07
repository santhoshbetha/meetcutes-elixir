defmodule Meetcutes.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    timezone_children =
      if Application.get_env(:meetcutes, :start_tz_updater, true) do
        [Tz.UpdatePeriodically]
      else
        []
      end

    children =
      [
        MeetcutesWeb.Telemetry,
        Meetcutes.Repo,
        # Start the PubSub system
        {Phoenix.PubSub, name: Meetcutes.PubSub},
        # Start the Presence system
        MeetcutesWeb.Presence,
        # Start Finch for HTTP requests
        {Finch, name: Meetcutes.Finch},
        # ETS-backed search rate limiter
        {Meetcutes.RateLimit, clean_period: :timer.minutes(10)},
        # Start Oban for background job processing
        {Oban, Application.fetch_env!(:meetcutes, Oban)},
        # Start the cleanup scheduler
        Meetcutes.Scheduler,
        # Start to serve requests, typically the last entry
        MeetcutesWeb.Endpoint
      ]
      |> Kernel.++(timezone_children)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Meetcutes.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MeetcutesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
