defmodule MeetcutesWeb.SessionController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Accounts
  alias Meetcutes.Accounts.User
  alias Meetcutes.Matching
  alias MeetcutesWeb.UserJSON

  # 1. EMAIL + PASSWORD LOGIN
  def create(conn, %{
        "action" => "password",
        "user" => %{"email" => email, "password" => password}
      }) do
    case Accounts.get_user_by_email_and_password(email, password) do
      %User{confirmed_at: nil} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          status: "error",
          code: "email_not_confirmed",
          message: "Please confirm your email address before logging in.",
          email: email
        })

      %User{} = user ->
        user = reset_password_retry_count(user)
        user = Accounts.record_login(user)
        user = Matching.refresh_if_stale(user)
        token = Accounts.generate_user_session_token(user)

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          user: UserJSON.profile(user),
          message: "Welcome back!",
          token: token
        })

      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          status: "error",
          error: "Invalid email or password",
          message: "Invalid email or password"
        })
    end
  end

  # 2. MAGIC LINK LOGIN (Validates token sent via email link)
  def create(conn, %{"action" => "verify_magic_link", "user" => %{"token" => token}}) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, _expired_tokens}} ->
        user = Accounts.record_login(user)
        user = Matching.refresh_if_stale(user)
        token = Accounts.generate_user_session_token(user)

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          user: UserJSON.profile(user),
          message: "Welcome back!",
          token: token
        })

      {:error, :not_found} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "The link is invalid or it has expired."})
    end
  end

  # 3. MAGIC LINK REQUEST (Generates and emails verification link)
  def create(conn, %{"action" => "request_magic_link", "user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      # Point this directly to your separate FRONTEND React/Mobile URL wrapper layout
      Accounts.deliver_login_instructions(
        user,
        &"https://meetcutes.us##{&1}"
      )
    end

    # Keep a generic response payload to avoid revealing registered email profiles
    conn
    |> put_status(:ok)
    |> json(%{
      message:
        "If your email is in our system, you will receive instructions for logging in shortly."
    })
  end

  # 4. LOGOUT / DELETE SESSION
  def delete(conn, _params) do
    # Extract the bearer token; the context hashes it before deleting the row.
    with ["Bearer " <> token] <- get_req_header(conn, "authorization") do
      # Deletes the token reference row cleanly from your database ledger table
      Accounts.delete_user_session_token(token)

      conn
      |> put_status(:ok)
      |> json(%{message: "Logged out successfully."})
    else
      _missing_header ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing authorization bearer token."})
    end
  end

  # The legacy client used to reset this counter after login; the server owns
  # that bookkeeping now so a client can never manipulate it.
  defp reset_password_retry_count(%User{password_retry_count: count} = user)
       when is_integer(count) and count > 0 do
    case Accounts.update_user(user, %{password_retry_count: 0}) do
      {:ok, updated} -> updated
      {:error, _changeset} -> user
    end
  end

  defp reset_password_retry_count(user), do: user
end
