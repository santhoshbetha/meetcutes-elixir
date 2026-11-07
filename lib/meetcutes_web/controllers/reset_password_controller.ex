defmodule MeetcutesWeb.ResetPasswordController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Accounts

  # Intercept and validate the token before allowing a password update
  plug :get_user_by_reset_password_token when action in [:update]

  # 0. VALIDATE A RESET TOKEN (does not consume it)
  #
  # The React `/auth/confirm` page uses this to decide whether an emailed
  # recovery link is still usable before forwarding the user to the password
  # form. Validation is read-only, so a token can still be used afterwards.
  def show(conn, %{"token" => token}) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          message: "The reset password token is invalid or has expired."
        })

      _user ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "The reset password token is valid."})
    end
  end

  # 1. REQUEST PASSWORD RESET LINK (Sends Email)
  def create(conn, %{"user" => %{"email" => email}}) do
    email = String.trim(email)

    case Accounts.get_user_by_email(email) do
      nil ->
        # Always return 200 OK to prevent malicious user enumeration attacks.
        send_generic_success(conn)

      user ->
        attempts = Accounts.record_password_reset_attempt(user)

        if Accounts.password_reset_limit_exceeded?(attempts) do
          conn
          |> put_status(:too_many_requests)
          |> json(%{
            status: "error",
            code: "password_reset_limit_exceeded",
            message: "Password reset limit exceeded. Please contact support.",
            password_retry_count: attempts
          })
        else
          # Point this link explicitly to the React reset-password page.
          Accounts.deliver_user_reset_password_instructions(user, fn token ->
            "#{Accounts.frontend_url()}/changepassword?#{URI.encode_query(%{"token" => token})}"
          end)

          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            message:
              "If this email is associated with an account, a password reset link has been sent.",
            password_retry_count: attempts
          })
        end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{status: "error", message: "An email address is required."})
  end

  # 2. SUBMIT NEW PASSWORD (Fires update query)
  def update(conn, %{"user" => user_params}) do
    user = conn.assigns.user

    case Accounts.reset_user_password(user, user_params) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Password has been reset successfully",
          password_retry_count: 0
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  # 3. HELPER PLUG: Token Verification Guard
  defp get_user_by_reset_password_token(conn, _opts) do
    # Accept the token from the route, the top-level body, or the nested
    # `user` payload so both the legacy and v1 clients keep working.
    token = conn.params["token"] || get_in(conn.params, ["user", "token"])

    with token when is_binary(token) and token != "" <- token,
         user when not is_nil(user) <- Accounts.get_user_by_reset_password_token(token) do
      conn
      |> assign(:user, user)
      |> assign(:token, token)
    else
      _invalid_or_missing ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          status: "error",
          message: "The reset password token is invalid or has expired."
        })
        # CRUCIAL: Blocks execution thread from jumping down into update/2
        |> halt()
    end
  end

  defp send_generic_success(conn) do
    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      message: "If this email is associated with an account, a password reset link has been sent."
    })
  end
end
