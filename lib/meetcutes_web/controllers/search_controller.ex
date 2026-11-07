defmodule MeetcutesWeb.SearchController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Accounts
  alias Meetcutes.Accounts.User
  alias Meetcutes.Relationships
  alias MeetcutesWeb.Presence
  alias MeetcutesWeb.UserJSON

  action_fallback MeetcutesWeb.FallbackController

  plug MeetcutesWeb.Plugs.SearchRateLimit when action in [:users]

  @default_limit 20
  @max_limit 100

  # Helper functions for parameter parsing
  defp parse_float_param(params, key) do
    case Map.get(params, key) do
      nil ->
        nil

      value when is_binary(value) ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> nil
        end

      value when is_number(value) ->
        value

      _ ->
        nil
    end
  end

  defp parse_integer_param(params, key) do
    case Map.get(params, key) do
      nil ->
        nil

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> nil
        end

      value when is_integer(value) ->
        value

      _ ->
        nil
    end
  end

  defp limit_param(params) do
    params
    |> parse_integer_param("limit")
    |> normalize_limit()
  end

  defp normalize_limit(nil), do: @default_limit
  defp normalize_limit(limit) when limit < 1, do: @default_limit
  defp normalize_limit(limit) when limit > @max_limit, do: @max_limit
  defp normalize_limit(limit), do: limit

  defp offset_param(params) do
    case parse_integer_param(params, "offset") do
      offset when is_integer(offset) and offset >= 0 -> offset
      _ -> 0
    end
  end

  @doc """
  Searches for users with advanced filtering options.
  POST /api/search/users

  The authenticated viewer's gender strictly scopes the discovery feed to the
  opposite gender. Body params: query, latitude, longitude, distance_miles,
  gender (legacy hint), age_from, age_to.
  """
  def users(conn, params) do
    viewer = conn.assigns.current_user
    query = Map.get(params, "query", "")
    latitude = parse_float_param(params, "latitude")
    longitude = parse_float_param(params, "longitude")
    distance_miles = parse_float_param(params, "distance_miles")
    gender = Map.get(params, "gender")
    age_from = parse_integer_param(params, "age_from")
    age_to = parse_integer_param(params, "age_to")
    limit = limit_param(params)
    offset = offset_param(params)

    cond do
      distance_miles && (!latitude || !longitude) ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          status: "error",
          message: "Validation failed",
          errors: ["latitude and longitude are required when using distance_miles"]
        })

      age_from && age_to && age_from > age_to ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          status: "error",
          message: "Validation failed",
          errors: ["age_from cannot be greater than age_to"]
        })

      true ->
        search_opts =
          []
          |> maybe_put(:query, query != "" && query)
          |> maybe_put(:latitude, latitude)
          |> maybe_put(:longitude, longitude)
          |> maybe_put(:distance_miles, distance_miles)
          |> maybe_put(:gender, gender)
          |> maybe_put(:age_from, age_from)
          |> maybe_put(:age_to, age_to)
          |> Keyword.put(:viewer_id, viewer.id)
          |> Keyword.put(:viewer_gender, viewer.gender)
          |> Keyword.put(:limit, limit + 1)
          |> Keyword.put(:offset, offset)

        users = Accounts.search_users(search_opts)
        has_more = length(users) > limit
        users = Enum.take(users, limit)

        online_user_ids =
          Presence.list("global_presence")
          |> Map.keys()

        users_with_online_status =
          Enum.map(users, fn user ->
            user
            |> public_user_data()
            |> Map.put(:is_online, to_string(user.id) in online_user_ids)
            |> Map.put(:last_login_at, user.last_login_at)
            |> Map.put(:last_seen_at, user.last_seen_at)
          end)

        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          data: %{
            users: users_with_online_status,
            pagination: %{limit: limit, offset: offset, has_more: has_more}
          }
        })
    end
  end

  defp maybe_put(opts, _key, value) when value in [nil, false], do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  @doc """
  Searches for a single user by email, phone number, or nickname.
  Uses regex to automatically detect the type of identifier.

  A user is only returned when the matching discoverability setting
  (`email_search`, `phone_number_search`, or `user_handle_search`) allows it,
  so this endpoint never exposes contact details the owner opted out of.

  GET /api/search/user/:identifier
  """
  def user(conn, %{"identifier" => identifier}) do
    case detect_identifier_type(identifier) do
      :email ->
        search_by_email(conn, identifier)

      :phone ->
        search_by_phone(conn, identifier)

      :nickname ->
        search_by_nickname(conn, identifier)
    end
  end

  @doc """
  Gets user data by user ID.
  GET /api/search/user/id/:id
  """
  def user_by_id(conn, %{"id" => user_id}) do
    viewer = conn.assigns.current_user

    case Accounts.get_user(user_id) do
      nil ->
        not_found(conn)

      user ->
        if visible_to_viewer?(viewer, user) do
          conn
          |> put_status(:ok)
          |> json(%{status: "success", data: %{user_data: user_data(user)}})
        else
          not_found(conn)
        end
    end
  end

  # Helper function to detect identifier type using regex
  defp detect_identifier_type(identifier) do
    cond do
      Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, identifier) ->
        :email

      Regex.match?(~r/^(\+\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}$/, identifier) or
          Regex.match?(~r/^\+\d{10,15}$/, identifier) ->
        :phone

      true ->
        :nickname
    end
  end

  @doc """
  Searches for a single user by email.
  GET /api/search/user/email/:email
  """
  def user_by_email(conn, %{"email" => email}) do
    search_by_email(conn, email)
  end

  @doc """
  Searches for a single user by phone number.
  GET /api/search/user/phone/:phone
  """
  def user_by_phone(conn, %{"phone" => phone_number}) do
    search_by_phone(conn, phone_number)
  end

  @doc """
  Searches for a single user by nickname.
  GET /api/search/user/nickname/:nickname
  """
  def user_by_nickname(conn, %{"nickname" => nickname}) do
    search_by_nickname(conn, nickname)
  end

  defp add_online_status_to_user(user) do
    online_user_ids =
      Presence.list("global_presence")
      |> Map.keys()

    user
    |> public_user_data()
    |> Map.put(:is_online, to_string(user.id) in online_user_ids)
    |> Map.put(:last_login_at, user.last_login_at)
    |> Map.put(:last_seen_at, user.last_seen_at)
  end

  defp public_user_data(%User{} = user) do
    UserJSON.public_profile(user)
  end

  defp user_data(%User{} = user) do
    user
    |> UserJSON.public_profile()
    |> Map.merge(%{
      userid: user.id,
      userhandle: user.nickname,
      firstname: user.first_name
    })
  end

  defp visible_to_viewer?(%User{id: viewer_id}, %User{id: user_id}) when viewer_id == user_id,
    do: true

  defp visible_to_viewer?(viewer, user) do
    user.is_active == true and
      user.is_approved == true and
      not Relationships.hidden?(viewer.id, user.id) and
      visibility_preference(user) != "events-only"
  end

  defp visibility_preference(%User{settings: settings}) do
    Map.get(settings || %{}, "visibility_preference") ||
      Map.get(settings || %{}, "visibilitypreference") ||
      "both"
  end

  defp search_by_email(conn, email) do
    find_user(conn, Accounts.get_user_by_email(email), :email)
  end

  defp search_by_phone(conn, phone_number) do
    find_user(conn, Accounts.get_user_by_phone_number(phone_number), :phone)
  end

  defp search_by_nickname(conn, nickname) do
    find_user(conn, Accounts.get_user_by_nickname(nickname), :nickname)
  end

  defp find_user(conn, %User{} = user, channel) do
    viewer = conn.assigns.current_user

    if visible_to_viewer?(viewer, user) and discoverable_by?(user, channel) do
      conn
      |> put_status(:ok)
      |> json(%{status: "success", data: %{user: add_online_status_to_user(user)}})
    else
      not_found(conn)
    end
  end

  defp find_user(conn, _user, _channel), do: not_found(conn)

  # Single-user lookup honors the same discoverability switches the settings
  # page exposes. A missing email flag keeps the UI default (email search on);
  # phone and handle searches stay opt-in so a legacy `nil` never leaks a
  # phone number or handle the owner never chose to publish.
  defp discoverable_by?(%User{} = user, :email), do: user.email_search != false
  defp discoverable_by?(%User{} = user, :phone), do: user.phone_number_search == true
  defp discoverable_by?(%User{} = user, :nickname), do: user.user_handle_search == true

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{status: "error", message: "User not found"})
  end
end
