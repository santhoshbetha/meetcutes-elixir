defmodule MeetcutesWeb.RegistrationController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Accounts
  alias MeetcutesWeb.UserJSON

  require Logger

  @link_regex ~r"((?:http(s)?:\/\/)?[\w.-]+(?:\.[\w\.-]+)+[\w\-\._~%:/?#[\]@!\$&'\(\)\*\+,;=.]+)|[0-9a-z+\-\.]+:[0-9a-z$-_.+!*'(),]+"ui

  defp parse_bio(bio) when is_binary(bio) and bio != "" do
    bio
    |> html_escape("text/plain")
  end

  defp parse_bio("") do
    ""
  end

  defp html_escape(text, "text/plain") do
    Regex.split(@link_regex, text, include_captures: true)
    |> Enum.map_every(2, fn chunk ->
      {:safe, part} = Phoenix.HTML.html_escape(chunk)
      part
    end)
    |> Enum.join("")
  end

  # register new user
  @doc "POST /api/v1/accounts"
  def create(conn, %{"user" => user_params}) do
    # Adjust context module namespace alias if register_user lives in Meetcutes.Accounts
    case register_user(user_params) do
      {:ok, user} ->
        # New accounts must prove ownership of their email before a session is
        # issued. The email link lands on the React confirmation page.
        send_confirmation_instructions(user)

        conn
        |> put_status(:created)
        |> json(%{
          status: "success",
          message: "Registration successful. Please check your email to confirm your account.",
          data: %{user: UserJSON.profile(user)}
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", errors: errors})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{status: "error", message: "An unexpected error occurred during registration"})
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

  defp register_user(params) do
    params = stringify_keys(params)

    allowed_keys = [
      "email",
      "password",
      "password_confirmation",
      "username",
      "nickname",
      "first_name",
      "last_name",
      "phone_number",
      "age",
      "birthday",
      "bio",
      "gender",
      "ethnicity",
      "city",
      "state",
      "time_zone",
      "settings",
      "raw_lat",
      "raw_lon"
    ]

    params =
      params
      |> Map.take(allowed_keys)
      |> Map.put("bio", parse_bio(Map.get(params, "bio", "")))
      |> Map.put("nickname", params["nickname"] || params["username"])
      |> Map.put(
        "password_confirmation",
        Map.get(params, "password_confirmation", params["password"])
      )

    create_user(params)
  end

  defp create_user(params) do
    case Accounts.register_user(params) do
      {:ok, user} ->
        {:ok, user}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, other} ->
        {:error, other}
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp stringify_keys(other), do: other
end
