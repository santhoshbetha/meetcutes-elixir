defmodule MeetcutesWeb.UserJSON do
  @moduledoc """
  Serializes user records for JSON API responses.

  The API speaks canonical snake_case. Secrets such as `hashed_password` and
  `calendar_token` are never included. Coordinates are derived from the fuzzed
  geohash so a user's raw location is not exposed.
  """

  alias Meetcutes.Accounts.User
  alias Meetcutes.Uploads

  @public_fields ~w(
    id nickname first_name last_name gender ethnicity age birth_year city state bio
    facebook instagram linkedin avatar avatar_url banner banner_url images image_urls
    hide_last_name
    geohash latitude longitude questionaire_values questionaire_values_set
    integrity_score stewardship_score cognitive_score lifestyle_score
    empathy_score narcissism_flags overall_percentile completed_quiz
    user_state is_active is_approved invisible last_active_at last_seen_at
    time_zone updated_at
  )a

  @doc """
  Returns the full, client-safe profile for a user.
  """
  def profile(%User{} = user) do
    {latitude, longitude} = coordinates(user.geohash)
    settings = user.settings || %{}

    %{
      id: user.id,
      email: user.email,
      nickname: user.nickname,
      first_name: user.first_name,
      last_name: user.last_name,
      hide_last_name: user.hide_last_name,
      gender: user.gender,
      ethnicity: user.ethnicity,
      age: user.age,
      birth_year: user.birth_year,
      city: user.city,
      state: user.state,
      phone_number: user.phone_number,
      bio: user.bio,
      facebook: user.facebook,
      instagram: user.instagram,
      linkedin: user.linkedin,
      avatar: user.avatar,
      avatar_url: media_url(user, user.avatar),
      banner: user.banner,
      banner_url: media_url(user, user.banner),
      images: user.images || [],
      image_urls: image_urls(user),
      geohash: user.geohash,
      latitude: latitude,
      longitude: longitude,
      default_coords_set: user.default_coords_set,
      user_coords_set: user.user_coords_set,
      exact_coords_set: user.exact_coords_set,
      email_search: user.email_search,
      phone_number_search: user.phone_number_search,
      user_handle_search: user.user_handle_search,
      only_hundred_miles_visibility: user.only_hundred_miles_visibility,
      visibility_preference: visibility_preference(settings),
      visibility_preferences: visibility_preferences(user, settings),
      date_of_location: user.date_of_location,
      date_of_coordinates: user.date_of_coordinates,
      time_of_login: user.time_of_login,
      last_login_at: user.last_login_at,
      last_seen_at: user.last_seen_at,
      last_active_at: user.last_active_at,
      last_refreshed_at: user.last_refreshed_at,
      questionaire_values: user.questionaire_values,
      questionaire_values_set: user.questionaire_values_set,
      onetime_fees_paid: user.onetime_fees_paid,
      onetime_fees_required: user.onetime_fees_required,
      accepted_onetime_fees_amount: user.accepted_onetime_fees_amount,
      around_user_count: user.around_user_count || 0,
      around_user_count_updated_at: user.around_user_count_updated_at,
      subscription_expires_at: user.subscription_expires_at,
      subscription_active: subscription_active?(user.subscription_expires_at),
      user_state: user.user_state,
      email_verified: user.email_verified,
      previous_events_attendees_list: user.previous_events_attendees_list,
      previous_events_attendees_date: user.previous_events_attendees_date,
      password_retry_count: user.password_retry_count,
      id_verified: user.id_verified,
      registered_events: user.registered_events,
      created_events: user.created_events,
      settings: user.settings,
      uri: user.uri,
      time_zone: user.time_zone,
      is_active: user.is_active,
      is_locked: user.is_locked,
      is_approved: user.is_approved,
      is_confirmed: user.is_confirmed,
      invisible: user.invisible,
      notification_settings: user.notification_settings,
      password_reset_pending: user.password_reset_pending,
      deactivated: user.deactivated,
      approval_pending: user.approval_pending,
      confirmation_pending: user.confirmation_pending,
      terms_accepted: user.terms_accepted,
      integrity_score: user.integrity_score,
      stewardship_score: user.stewardship_score,
      cognitive_score: user.cognitive_score,
      lifestyle_score: user.lifestyle_score,
      empathy_score: user.empathy_score,
      narcissism_flags: user.narcissism_flags,
      overall_percentile: user.overall_percentile,
      completed_quiz: user.completed_quiz,
      confirmed_at: user.confirmed_at,
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end

  @doc """
  Returns the subset of profile data that other authenticated users may see.
  """
  def public_profile(%User{} = user) do
    user
    |> profile()
    |> Map.take(@public_fields)
  end

  defp coordinates(nil), do: {nil, nil}

  defp coordinates(geohash) when is_binary(geohash) do
    {latitude, longitude} = Geohash.decode(geohash)
    {latitude, longitude}
  rescue
    _ -> {nil, nil}
  end

  defp subscription_active?(nil), do: false

  defp subscription_active?(%DateTime{} = expires_at) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  defp subscription_active?(_expires_at), do: false

  defp visibility_preference(settings) do
    Map.get(settings, "visibility_preference") ||
      Map.get(settings, "visibilitypreference") ||
      "both"
  end

  defp visibility_preferences(user, settings) do
    %{
      visibility_preference: visibility_preference(settings),
      email_search: user.email_search,
      phone_number_search: user.phone_number_search,
      user_handle_search: user.user_handle_search,
      only_hundred_miles_visibility: user.only_hundred_miles_visibility
    }
  end

  defp media_url(_user, nil), do: nil

  defp media_url(_user, %{"url" => url}) when is_binary(url), do: url
  defp media_url(_user, %{url: url}) when is_binary(url), do: url

  defp media_url(user, %{"filename" => filename}) when is_binary(filename) do
    storage_url(user, filename)
  end

  defp media_url(user, %{filename: filename}) when is_binary(filename) do
    storage_url(user, filename)
  end

  defp media_url(user, filename) when is_binary(filename), do: storage_url(user, filename)
  defp media_url(_user, _other), do: nil

  defp image_urls(%User{} = user) do
    user.images
    |> List.wrap()
    |> Enum.map(fn
      "" -> nil
      "http" <> _rest = url -> url
      filename when is_binary(filename) -> storage_url(user, filename)
      _other -> nil
    end)
  end

  defp storage_url(user, filename) do
    Uploads.url(user, filename)
  rescue
    _ -> filename
  end
end
