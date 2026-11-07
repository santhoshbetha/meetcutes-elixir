defmodule MeetcutesWeb.SettingsController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Accounts
  alias Meetcutes.Matching

  alias MeetcutesWeb.UserJSON

  plug :assign_email_and_password_changesets

  def update(conn, %{
        "action" => "update_email",
        "user" => %{"current_password" => password} = user_params
      }) do
    user = conn.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        case Accounts.deliver_user_update_email_instructions(
               applied_user,
               user.email,
               &Accounts.email_change_url/1
             ) do
          {:ok, _email_or_job} ->
            conn
            |> put_status(:accepted)
            |> json(%{
              status: "success",
              message:
                "A link to confirm your email change has been sent to your new email address."
            })

          {:error, _reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{
              status: "error",
              message: "Could not send the email change confirmation link. Please try again."
            })
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  def update(conn, %{
        "action" => "update_password",
        "user" => %{"current_password" => password} = user_params
      }) do
    user = conn.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, {updated_user, _expired_tokens}} ->
        token = Accounts.generate_user_session_token(updated_user)

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Password has been reset successfully",
          token: token
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: "Failed to update password."})
    end
  end

  def update(conn, %{"action" => "update_nickname", "user" => %{"nickname" => nickname}}) do
    user = conn.assigns.current_user

    case Accounts.update_user_nickname(user, nickname) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Nickname has been updated successfully",
          user: UserJSON.profile(updated_user)
        })

      {:error, :nickname_taken} ->
        conn
        |> put_status(:conflict)
        |> json(%{status: "error", message: "Nickname is already taken."})

      {:error, :invalid_nickname} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: "Invalid nickname."})

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  def update(conn, %{"action" => "update_email_direct", "user" => %{"email" => email}}) do
    user = conn.assigns.current_user

    case Accounts.update_user_email_direct(user, email) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Email has been updated successfully",
          user: UserJSON.profile(updated_user)
        })

      {:error, :email_taken} ->
        conn
        |> put_status(:conflict)
        |> json(%{status: "error", message: "Email is already taken."})

      {:error, :invalid_email} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: "Invalid email."})

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  def update(conn, %{
        "action" => "update_phone_number",
        "user" => %{"phone_number" => phone_number}
      }) do
    user = conn.assigns.current_user

    case Accounts.update_user_phone_number(user, phone_number) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Phone number has been updated successfully",
          user: UserJSON.profile(updated_user)
        })

      {:error, :phone_number_taken} ->
        conn
        |> put_status(:conflict)
        |> json(%{status: "error", message: "Phone number is already taken."})

      {:error, :invalid_phone_number} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: "Invalid phone number."})

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  def update(conn, %{"action" => "update_location", "user" => %{"city" => city, "state" => state}}) do
    user = conn.assigns.current_user

    case Accounts.update_user_location(user, %{city: city, state: state}) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Location has been updated successfully",
          user: UserJSON.profile(updated_user)
        })

      {:error, :location_change_limit_exceeded} ->
        days_remaining = Accounts.days_until_location_change(user)

        conn
        # 403 Forbidden is the correct semantic code for business-rule permission rejections
        |> put_status(:forbidden)
        |> json(%{
          status: "error",
          message:
            "Location can only be changed once per month. #{days_remaining} days remaining."
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  def update(conn, %{
        "action" => "update_coordinates",
        "user" => %{"latitude" => latitude, "longitude" => longitude}
      }) do
    user = conn.assigns.current_user

    case Accounts.update_user_coordinates(user, %{latitude: latitude, longitude: longitude}) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Coordinates have been updated successfully",
          user: UserJSON.profile(updated_user)
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    user = conn.assigns.current_user

    # Fixed the pattern match to capture the updated user struct returned by the context layer
    case Accounts.update_user_email(user, token) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Email has been updated successfully",
          user: UserJSON.profile(updated_user)
        })

      _error ->
        conn
        # 422 is more semantically accurate for expired token validation than 401
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Email change link is invalid or it has expired."})
    end
  end

  def update_profile(conn, %{"user" => user_params}) do
    user = conn.assigns.current_user

    # Use your changeset wrapper to process parameter changes safely
    changeset = Meetcutes.Accounts.User.profile_changeset(user, user_params)

    case Meetcutes.Repo.update(changeset) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Profile has been updated successfully",
          user: UserJSON.profile(updated_user)
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        # Formats validation errors into flat key/value pairs for React
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  def update_user(conn, %{"user" => user_params}) do
    user = conn.assigns.current_user

    # Ensure User is correctly referenced via your Accounts context module if applicable
    # e.g., Meetcutes.Accounts.update_user(user, user_params)
    case Meetcutes.Accounts.update_user(user, user_params) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Profile has been updated successfully",
          user: UserJSON.profile(updated_user)
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        # Formats validation errors into clean key/value pairs for your frontend
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  @doc """
  Updates the user's time zone.
  Expected JSON: %{"time_zone" => "America/Los_Angeles"}
  """
  def update_timezone(conn, %{"user" => %{"time_zone" => tz_string}}) do
    user = conn.assigns.current_user

    case Accounts.update_user_profile(user, %{time_zone: tz_string}) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Time zone has been updated successfully",
          user: UserJSON.profile(updated_user)
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        # Formats validation errors into clean key/value pairs for your React frontend
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Validation failed", errors: errors})
    end
  end

  def profile(conn, _params) do
    user = conn.assigns.current_user
    user = Matching.refresh_if_stale(user)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      message: "Profile retrieved successfully",
      user: UserJSON.profile(user)
    })
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    user = conn.assigns.current_user

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
  end

  @doc """
  Soft deletes the current user account.
  DELETE /api/users/settings
  """
  def delete(conn, _params) do
    user = conn.assigns.current_user

    case Accounts.soft_delete_user(user) do
      {:ok, _deleted_user} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Account successfully deleted"})

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Delete failed", errors: errors})
    end
  end

  @doc """
  Gets the current user's location change status.
  GET /api/users/settings/location_status
  """
  def location_status(conn, _params) do
    # Fixed the pattern match style to check your flat current_user assign
    user = conn.assigns.current_user

    can_change = Accounts.can_change_location?(user)
    days_remaining = Accounts.days_until_location_change(user)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: %{
        can_change: can_change,
        days_remaining: days_remaining
      }
    })
  end

  @doc """
  Gets a websocket authentication token for the current user.
  GET /api/users/settings/websocket_token
  """
  def websocket_token(conn, _params) do
    # Fixed the pattern match style to match current_user
    user = conn.assigns.current_user
    token = Accounts.generate_websocket_token(user)

    conn
    |> put_status(:ok)
    |> json(%{status: "success", message: "Websocket token retrieved successfully", token: token})
  end
end
