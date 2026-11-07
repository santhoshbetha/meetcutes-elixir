defmodule Meetcutes.Repo do
  use Ecto.Repo,
    otp_app: :meetcutes,
    adapter: Ecto.Adapters.Postgres
end
