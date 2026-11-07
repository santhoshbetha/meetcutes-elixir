# Fast paywall override for manual QA.
#
# Run with:
#
#     mix run priv/repo/seed_paywall_test.exs
#
# This forces the first deterministic Austin demo account (Alex) over the
# 200-match premium threshold without deleting or rebuilding the rest of the
# seed dataset. Log in with:
#
#     austin.demo.alex@meetcutes.test / Password123!
#
# The next `mix run priv/repo/seeds.exs` rebuild resets the override.

defmodule Meetcutes.SeedPaywallTest do
  @moduledoc false

  alias Meetcutes.Accounts.User
  alias Meetcutes.Repo

  @email "austin.demo.alex@meetcutes.test"

  def run do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(User, email: @email) do
      nil ->
        IO.puts("""
        Could not find #{@email}.
        Run `mix run priv/repo/seeds.exs` first, then rerun this override.
        """)

        System.halt(1)

      user ->
        updated =
          user
          |> Ecto.Changeset.change(%{
            around_user_count: 205,
            around_user_count_updated_at: now,
            subscription_expires_at: nil
          })
          |> Repo.update!()

        IO.puts("""
        Paywall override applied:
          email: #{updated.email}
          around_user_count: #{updated.around_user_count}
          subscription_expires_at: #{inspect(updated.subscription_expires_at)}
          login: #{updated.email} / Password123!
        """)
    end
  end
end

Meetcutes.SeedPaywallTest.run()
