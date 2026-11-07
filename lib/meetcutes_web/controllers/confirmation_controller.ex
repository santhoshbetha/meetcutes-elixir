defmodule MeetcutesWeb.ConfirmationController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Accounts
  alias Meetcutes.Accounts.User
  alias MeetcutesWeb.UserJSON

  require Logger

  @generic_resend_message "If this email is associated with an unconfirmed account, a confirmation link has been sent."

  # 1. RESEND CONFIRMATION LINK
  #
  # Always responds with the same message so the endpoint cannot be used to
  # discover which email addresses have accounts.
  def resend(conn, %{"user" => %{"email" => email}}) do
    case Accounts.get_user_by_email(email) do
      %User{confirmed_at: nil} = user ->
        send_confirmation_instructions(user)

      _missing_or_confirmed ->
        :ok
    end

    conn
    |> put_status(:ok)
    |> json(%{status: "success", message: @generic_resend_message})
  end

  def resend(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{status: "error", message: "An email address is required."})
  end

  # 2. VERIFY EMAIL TOKEN (Pure Asynchronous JSON endpoint called by React)
  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Email confirmed successfully",
          user: UserJSON.profile(user)
        })

      :error ->
        # If token is invalid or expired, return a 422 JSON payload directly
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "The confirmation link is invalid or has expired."})
    end
  end

  defp send_confirmation_instructions(user) do
    url_fun = fn token ->
      query = URI.encode_query(%{"token" => token, "email" => user.email})
      "#{Accounts.frontend_url()}/email-verification?#{query}"
    end

    case Accounts.deliver_user_confirmation_instructions(user, url_fun) do
      {:ok, _email_or_job} ->
        :ok

      {:error, :already_confirmed} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to send confirmation instructions for user #{user.id}: #{inspect(reason)}"
        )

        :error
    end
  end
end
