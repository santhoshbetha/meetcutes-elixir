defmodule Meetcutes.Workers.MailerWorker do
  use Meetcutes.Workers.WorkerHelper, queue: "mailer"

  import Swoosh.Email

  alias Meetcutes.Accounts.User
  alias Meetcutes.Emails.{Layout, Mailer}

  @impl Oban.Worker
  def perform(%Job{
        args: %{"op" => "email", "encoded_email" => encoded_email, "config" => config}
      }) do
    email =
      encoded_email
      |> Base.decode64!()
      |> :erlang.binary_to_term()

    Mailer.perform(:deliver_async, email, config)
  end

  @doc """
  Builds and delivers a match-reminder email from inside the Oban mailer queue.

  The `NotificationWorker` calls this after loading the recipient and matched
  profile from Ecto. Delivery goes through `Meetcutes.Emails.Mailer`, which uses
  the configured Swoosh Resend adapter and the shared Finch client.
  """
  def deliver_match_reminder(%User{} = target_user, %User{} = matched_profile) do
    case recipient_email(target_user) do
      nil ->
        {:error, :missing_recipient}

      recipient ->
        recipient
        |> build_match_reminder(target_user, matched_profile)
        |> Mailer.deliver()
        |> case do
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(10)

  defp build_match_reminder(recipient, target_user, matched_profile) do
    name = display_name(target_user)
    profile_url = Layout.frontend_url("/user/#{matched_profile.id}")

    text_body = """
    Hi #{name},

    someone new just popped up in your Austin discovery pool! Click here to view your new match profile:

    #{profile_url}

    You're receiving this because you and another member liked each other on Meetcutes.
    """

    html_body =
      [
        Layout.paragraph("Hi #{name},"),
        Layout.paragraph("someone new just popped up in your Austin discovery pool!"),
        Layout.paragraph_with_link(
          "",
          profile_url,
          "Click here",
          " to view your new match profile."
        ),
        Layout.muted(
          "You're receiving this because you and another member liked each other on Meetcutes."
        )
      ]
      |> Enum.join("\n")
      |> then(
        &Layout.document(
          "You have a new match",
          "Someone new just popped up in your discovery pool.",
          &1
        )
      )

    new()
    |> to(recipient)
    |> from(Layout.from())
    |> subject("Someone new is waiting for you on Meetcutes")
    |> text_body(text_body)
    |> html_body(html_body)
  end

  defp recipient_email(%User{email: email}) when is_binary(email) do
    case String.trim(email) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp recipient_email(_user), do: nil

  defp display_name(%User{first_name: first_name} = user) when is_binary(first_name) do
    case String.trim(first_name) do
      "" -> fallback_name(user)
      name -> name
    end
  end

  defp display_name(%User{} = user), do: fallback_name(user)
  defp display_name(_user), do: "there"

  defp fallback_name(%User{nickname: nickname}) when is_binary(nickname) and nickname != "",
    do: nickname

  defp fallback_name(%User{email: email}) when is_binary(email) and email != "", do: email
  defp fallback_name(_user), do: "there"
end
