defmodule Meetcutes.Workers.NotificationWorker do
  @moduledoc """
  Asynchronous match-reminder fan-out.

  Controllers and context modules enqueue a tiny job with the recipient and
  matched profile ids. The worker loads both Ecto records and performs the
  Resend request off the request lifecycle thread.

  Returning `{:cancel, reason}` marks permanent conditions (missing or deleted
  profiles, missing recipient address) as non-retryable. Delivery errors are
  returned as `{:error, reason}` so Oban can retry transient API failures.
  """

  use Oban.Worker, queue: :mailer, max_attempts: 3

  alias Meetcutes.Accounts.User
  alias Meetcutes.Repo
  alias Meetcutes.Workers.MailerWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case fetch(args, :action) do
      "match_reminder" -> deliver_match_reminder(args)
      :match_reminder -> deliver_match_reminder(args)
      other -> {:cancel, {:unsupported_action, other}}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(15)

  defp deliver_match_reminder(args) do
    with user_id when is_binary(user_id) <- fetch(args, :user_id),
         match_id when is_binary(match_id) <- fetch(args, :match_id),
         %User{deleted_at: nil} = target_user <- Repo.get(User, user_id),
         %User{deleted_at: nil} = matched_profile <- Repo.get(User, match_id) do
      case MailerWorker.deliver_match_reminder(target_user, matched_profile) do
        :ok -> :ok
        {:error, :missing_recipient} -> {:cancel, :missing_recipient}
        {:error, reason} -> {:error, reason}
      end
    else
      _missing_profile_or_argument -> {:cancel, :profile_not_found}
    end
  end

  defp fetch(args, key) when is_map(args) do
    Map.get(args, Atom.to_string(key), Map.get(args, key))
  end
end
