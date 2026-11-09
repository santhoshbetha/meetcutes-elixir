defmodule Meetcutes.Accounts.UserNotifier do
  import Swoosh.Email

  alias Meetcutes.Accounts.User
  alias Meetcutes.Emails.{Layout, Mailer}

  # Delivers the email using the queued application mailer. The email struct is
  # returned so callers (and tests) can inspect the rendered bodies without
  # waiting for the Oban worker.
  defp deliver(recipient, subject, text_body, html_body \\ nil) do
    email =
      new()
      |> to(recipient)
      |> from(Layout.from())
      |> subject(subject)
      |> text_body(text_body)
      |> put_html_body(html_body)

    with {:ok, _metadata} <- Mailer.deliver_async(email) do
      {:ok, email}
    end
  end

  defp put_html_body(email, nil), do: email
  defp put_html_body(email, html) when is_binary(html), do: html_body(email, html)

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    reset_url = Layout.ensure_absolute_url(url)
    name = display_name(user)

    text_body = """
    Hi #{name},

    You requested a password reset for your Meetcutes account.

    This secure link is valid for the next 24 hours:

    #{reset_url}

    If you didn't request this change, you can safely ignore this email. Your
    password will not change until you create a new one.
    """

    html_body =
      [
        Layout.paragraph("Hi #{name},"),
        Layout.paragraph(
          "We received a request to reset the password for your Meetcutes account. This secure link is valid for the next 24 hours."
        ),
        Layout.button("Reset my password", reset_url),
        Layout.muted(
          "If you didn't request this change, you can safely ignore this email. Your password will not change until you create a new one."
        )
      ]
      |> Enum.join("\n")

    deliver(
      user.email,
      "Reset your Meetcutes password",
      text_body,
      Layout.document(
        "Reset your Meetcutes password",
        "A secure link to reset your Meetcutes password is ready.",
        html_body
      )
    )
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{display_name(user)},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{display_name(user)},

    Welcome to Meetcutes.us!

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{display_name(user)},

    Welcome to Meetcutes.us!

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

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
