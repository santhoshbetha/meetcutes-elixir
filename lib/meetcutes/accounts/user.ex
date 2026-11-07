defmodule Meetcutes.Accounts.User do
  use Meetcutes.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Meetcutes.GeoPrivacy

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_confirmation, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :current_password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime

    field :nickname, :string
    field :avatar, :map
    field :banner, :map
    field :images, {:array, :string}, default: []
    field :first_name, :string
    field :last_name, :string
    field :hide_last_name, :boolean, default: false
    field :gender, :string
    field :ethnicity, :string
    field :birthday, :date, virtual: true
    field :age, :integer
    field :city, :string
    field :state, :string
    field :phone_number, :string
    field :facebook, :string
    field :instagram, :string
    field :linkedin, :string
    field :birth_year, :integer

    field :bio, :string, default: ""

    field :geohash, :string

    field :default_coords_set, :boolean
    field :user_coords_set, :boolean
    field :exact_coords_set, :boolean
    field :email_search, :boolean
    field :phone_number_search, :boolean
    field :user_handle_search, :boolean
    field :only_hundred_miles_visibility, :boolean

    field :date_of_location, :utc_datetime
    field :date_of_coordinates, :utc_datetime
    field :time_of_login, :utc_datetime
    field :last_login_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :last_active_at, :naive_datetime
    field :last_refreshed_at, :naive_datetime_usec
    field :authenticated_at, :utc_datetime, virtual: true

    field :around_user_count, :integer, default: 0
    field :around_user_count_updated_at, :utc_datetime
    field :subscription_expires_at, :utc_datetime
    field :stripe_customer_id, :string

    field :questionaire_values, :map
    field :questionaire_values_set, :boolean
    field :onetime_fees_paid, :boolean
    field :onetime_fees_required, :boolean
    field :accepted_onetime_fees_amount, :integer
    field :user_state, Ecto.Enum, values: [:active, :inactive, :suspended, :delete]
    field :email_verified, :boolean
    field :previous_events_attendees_list, {:array, :string}
    field :registered_events, {:array, :map}
    field :created_events, {:array, :map}
    field :previous_events_attendees_date, :utc_datetime
    field :password_retry_count, :integer
    field :id_verified, :boolean

    field :settings, :map, default: nil
    field :uri, :string, default: nil
    field :calendar_token, :string

    field :time_zone, :string, default: "UTC"

    field :is_active, :boolean, default: true
    field :is_locked, :boolean, default: false
    field :is_approved, :boolean, default: true
    field :is_confirmed, :boolean, default: false
    field :invisible, :boolean, default: false
    field :notification_settings, :map, default: %{}

    field :password_reset_pending, :boolean, default: false
    field :deactivated, :boolean, default: false
    field :approval_pending, :boolean, default: false
    field :confirmation_pending, :boolean, default: false

    field :terms_accepted, :boolean

    field :deleted_at, :utc_datetime

    field :integrity_score, :integer, default: 0
    field :stewardship_score, :integer, default: 0
    # The IQ proxy
    field :cognitive_score, :integer, default: 0
    field :lifestyle_score, :integer, default: 0
    # The EQ proxy
    field :empathy_score, :integer, default: 0
    field :narcissism_flags, :integer, default: 0

    # Percentage of total possible points (for percentiles)
    field :overall_percentile, :float, default: 0.0
    field :completed_quiz, :boolean, default: false

    has_many :user_responses, Meetcutes.Surveys.UserResponse

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for general updates.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :first_name,
      :last_name,
      :hide_last_name,
      :nickname,
      :gender,
      :ethnicity,
      :city,
      :state,
      :phone_number,
      # Already in your list, which is good!
      :time_zone,
      :bio,
      :geohash,
      :default_coords_set,
      :user_coords_set,
      :exact_coords_set,
      :email_search,
      :phone_number_search,
      :user_handle_search,
      :only_hundred_miles_visibility,
      :date_of_location,
      :date_of_coordinates,
      :time_of_login,
      :last_login_at,
      :last_active_at,
      :last_refreshed_at,
      :questionaire_values,
      :questionaire_values_set,
      :onetime_fees_paid,
      :onetime_fees_required,
      :accepted_onetime_fees_amount,
      :user_state,
      :email_verified,
      :previous_events_attendees_list,
      :registered_events,
      :created_events,
      :previous_events_attendees_date,
      :password_retry_count,
      :id_verified,
      :settings,
      :uri,
      :is_active,
      :is_locked,
      :is_approved,
      :is_confirmed,
      :invisible,
      :notification_settings,
      :password_reset_pending,
      :deactivated,
      :approval_pending,
      :confirmation_pending,
      :terms_accepted,
      :deleted_at,
      :integrity_score,
      :stewardship_score,
      :cognitive_score,
      :lifestyle_score,
      :overall_percentile,
      :completed_quiz
    ])
    |> generate_fuzzed_geohash(attrs)
    |> validate_length(:first_name, max: 100)
    |> validate_length(:last_name, max: 100)
    |> validate_length(:nickname, max: 100)
    |> validate_length(:ethnicity, max: 100)
    |> validate_length(:phone_number, max: 20)
    # NEW: Validate that the string is a valid IANA timezone (e.g., "America/Chicago")
    # This uses the TzExtra library for comprehensive IANA timezone validation
    |> validate_inclusion(:time_zone, get_valid_timezones())
  end

  @doc """
  A user changeset for registration.

  It is important to validate the length of both email and password.
  Otherwise databases may truncate the email without warnings, which
  could lead to unpredictable or insecure behaviour. Long passwords may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.

    * `:validate_email` - Validates the uniqueness of the email, in case
      you don't want to validate the uniqueness of the email (like when
      using this changeset for validations on a LiveView form before
      submitting the form), this option can be set to `false`.
      Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    changeset =
      user
      |> cast(attrs, [
        :email,
        :password,
        :password_confirmation,
        :first_name,
        :last_name,
        :nickname,
        :birthday,
        :age,
        :gender,
        :ethnicity,
        :city,
        :state,
        :phone_number,
        :time_zone,
        :settings,
        :is_confirmed
      ])
      |> put_change(:is_confirmed, false)
      |> put_change(:user_state, :active)
      |> put_default_accepted_membership_fee()
      |> generate_fuzzed_geohash(attrs)
      |> put_default_coordinate_flags()
      |> normalize_registration_age_fields()
      |> validate_required([:first_name, :last_name])
      |> validate_length(:first_name, max: 100)
      |> validate_length(:last_name, max: 100)
      |> validate_length(:nickname, max: 100)
      |> validate_length(:ethnicity, max: 100)
      |> validate_length(:phone_number, max: 20)
      |> validate_email(opts)
      |> validate_phone_number(opts)

    # Only validate password if it's provided
    if get_change(changeset, :password) do
      changeset
      |> validate_password(opts)
      |> validate_confirmation(:password, message: "does not match password")
    else
      changeset
    end
  end

  defp validate_phone_number(changeset, opts) do
    changeset
    |> validate_required([:phone_number])
    |> validate_format(:phone_number, ~r/^[\+]?[1-9][\d]{0,15}$/,
      message: "must be a valid phone number"
    )
    |> validate_length(:phone_number, max: 20)
    |> maybe_validate_unique_phone_number(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Pbkdf2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_phone_number(changeset, opts) do
    if Keyword.get(opts, :validate_phone_number, true) do
      changeset
      |> unsafe_validate_unique(:phone_number, Meetcutes.Repo)
      |> unique_constraint(:phone_number)
    else
      changeset
    end
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Meetcutes.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc """
  A user changeset for claiming a public handle.

  Handles are 5–15 characters, start with a letter, and contain only letters,
  numbers, or underscores. The uniqueness check is case-insensitive.
  """
  def handle_changeset(user, handle) when is_binary(handle) do
    user
    |> change(nickname: handle)
    |> validate_required(:nickname)
    |> validate_format(
      :nickname,
      ~r/^[A-Za-z][A-Za-z0-9_]{4,14}$/,
      message:
        "must be 5-15 characters, start with a letter, and contain only letters, numbers, or underscores"
    )
    |> maybe_validate_unique_nickname()
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  @doc """
  Confirms the account by setting `confirmed_at` and the confirmation flags.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)

    change(user,
      confirmed_at: now,
      is_confirmed: true,
      email_verified: true,
      confirmation_pending: false
    )
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Pbkdf2.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Meetcutes.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Pbkdf2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Pbkdf2.no_user_verify()
    false
  end

  defp normalize_registration_age_fields(changeset) do
    today = Date.utc_today()
    birthday = get_change(changeset, :birthday)
    age = get_change(changeset, :age)

    cond do
      birthday ->
        calculated_age = Date.diff(today, birthday) |> div(365)

        changeset
        |> put_change(:age, calculated_age)
        |> put_change(:birth_year, birthday.year)

      is_integer(age) and age >= 0 ->
        put_change(changeset, :birth_year, today.year - age)

      true ->
        changeset
    end
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    changeset = cast(changeset, %{current_password: password}, [:current_password])

    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  # usage of below:
  # user = Repo.get(User, user_id)
  # cleaned_user = User.clean_past_events(user)

  @doc """
  Updates a user with the given attributes using the general changeset.
  This is a convenience method for updating user fields.
  """
  def update_changeset(user, attrs) do
    changeset(user, attrs)
  end

  @doc """
  Updates a user with the given attributes in the database.
  This function performs the actual database update using update_changeset.
  """
  def update_user(%__MODULE__{} = user, attrs) do
    update_changeset(user, attrs)
    |> Meetcutes.Repo.update()
  end

  @doc """
  Updates a user profile with the fields the API allows clients to change.

  Media metadata (`avatar`/`banner`) is deliberately excluded: those are only
  ever written by the upload pipeline after the file has been validated.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :first_name,
      :last_name,
      :hide_last_name,
      :nickname,
      :gender,
      :ethnicity,
      :city,
      :state,
      :phone_number,
      :bio,
      :geohash,
      :facebook,
      :instagram,
      :linkedin,
      :time_zone,
      :settings,
      :notification_settings,
      :email_search,
      :phone_number_search,
      :user_handle_search,
      :only_hundred_miles_visibility,
      :default_coords_set,
      :user_coords_set,
      :exact_coords_set,
      :date_of_location,
      :date_of_coordinates,
      :time_of_login,
      :last_login_at,
      :last_seen_at,
      :last_active_at,
      :last_refreshed_at,
      :questionaire_values,
      :questionaire_values_set,
      :previous_events_attendees_list,
      :previous_events_attendees_date,
      :terms_accepted
    ])
    |> generate_fuzzed_geohash(attrs)
    |> validate_length(:first_name, max: 100)
    |> validate_length(:last_name, max: 100)
    |> validate_length(:nickname, max: 100)
    |> validate_length(:ethnicity, max: 100)
    |> validate_length(:phone_number, max: 20)
    |> validate_length(:bio, max: 500)
    |> maybe_validate_unique_nickname()
    |> validate_phone_number_profile()
    |> validate_inclusion(:time_zone, get_valid_timezones())
  end

  @doc """
  Writes the ordered photo list for a user.

  Only the upload pipeline should call this: every entry is a storage filename
  produced by `Meetcutes.Uploads`, and empty strings mark unused slots. It uses
  `change/2` rather than `cast/3` because casting an `{:array, :string}`
  discards empty strings, which would silently collapse the slot positions.
  """
  def images_changeset(user, images) when is_list(images) do
    user
    |> change(images: images)
    |> validate_length(:images, max: 10)
    |> validate_change(:images, fn :images, images ->
      if Enum.all?(images, &(is_binary(&1) and byte_size(&1) <= 500)) do
        []
      else
        [images: "must be a list of image paths"]
      end
    end)
  end

  @doc """
  Writes media metadata that has already been produced by the upload pipeline.
  """
  def media_changeset(user, attrs) do
    cast(user, attrs, [:avatar, :banner])
  end

  defp maybe_validate_unique_nickname(changeset) do
    case get_change(changeset, :nickname) do
      nil ->
        changeset

      nickname ->
        query =
          from(u in __MODULE__,
            where:
              fragment("lower(?) = lower(?)", u.nickname, ^nickname) and
                is_nil(u.deleted_at)
          )

        query =
          if changeset.data.id do
            from(u in query, where: u.id != ^changeset.data.id)
          else
            query
          end

        changeset =
          if Meetcutes.Repo.exists?(query) do
            add_error(changeset, :nickname, "has already been taken")
          else
            changeset
          end

        unique_constraint(changeset, :nickname,
          name: :users_lower_nickname_index,
          message: "has already been taken"
        )
    end
  end

  defp validate_phone_number_profile(changeset) do
    if get_change(changeset, :phone_number) do
      changeset
      |> validate_format(:phone_number, ~r/^[\+]?[1-9][\d]{0,15}$/,
        message: "must be a valid phone number"
      )
      |> unsafe_validate_unique(:phone_number, Meetcutes.Repo)
      |> unique_constraint(:phone_number)
    else
      changeset
    end
  end

  # The fee agreed at signup is stored on the user so a later public price
  # change never reprices an existing account. Admins can still override the
  # value through the general user changeset.
  defp put_default_accepted_membership_fee(changeset) do
    if get_field(changeset, :accepted_onetime_fees_amount) do
      changeset
    else
      fee =
        :meetcutes
        |> Application.get_env(:membership_fee_usd, 50)
        |> normalize_membership_fee()

      put_change(changeset, :accepted_onetime_fees_amount, fee)
    end
  end

  defp normalize_membership_fee(fee) when is_integer(fee) and fee > 0, do: fee
  defp normalize_membership_fee(_fee), do: 50

  defp generate_fuzzed_geohash(changeset, %{"raw_lat" => lat, "raw_lon" => lon}) do
    with {:ok, lat} <- parse_coordinate(lat),
         {:ok, lon} <- parse_coordinate(lon) do
      {fuzzed_lat, fuzzed_lon} = GeoPrivacy.fuzz_coordinates(lat, lon)

      hash = Geohash.encode(fuzzed_lat, fuzzed_lon, 9)
      put_change(changeset, :geohash, hash)
    else
      _invalid_coordinates -> changeset
    end
  end

  defp generate_fuzzed_geohash(changeset, _), do: changeset

  # Signup coordinates come from the selected registration city, not from a
  # manual map interaction. Mark them as a system default until the user saves
  # an explicit location in the location workspace.
  defp put_default_coordinate_flags(changeset) do
    if get_change(changeset, :geohash) do
      changeset
      |> put_change(:default_coords_set, true)
      |> put_change(:user_coords_set, false)
      |> put_change(:exact_coords_set, false)
    else
      changeset
    end
  end

  defp parse_coordinate(value) when is_number(value), do: {:ok, value}

  defp parse_coordinate(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _invalid -> :error
    end
  end

  defp parse_coordinate(_value), do: :error

  @doc """
  Removes past events from registered_events and created_events arrays.
  Assumes each map in the arrays has an "event_date" key with UTC datetime.
  """
  def clean_past_events(%__MODULE__{} = user) do
    now = DateTime.utc_now()

    registered_events = filter_future_events(user.registered_events || [], now)
    created_events = filter_future_events(user.created_events || [], now)

    %{user | registered_events: registered_events, created_events: created_events}
  end

  defp filter_future_events(events, now) do
    Enum.filter(events, fn event_map ->
      case event_map["event_date"] do
        # keep if no date
        nil ->
          true

        date when is_binary(date) ->
          case DateTime.from_iso8601(date) do
            {:ok, dt, _} -> DateTime.compare(dt, now) != :lt
            # keep if invalid date
            _ -> true
          end

        %DateTime{} = dt ->
          DateTime.compare(dt, now) != :lt

        # keep if unexpected format
        _ ->
          true
      end
    end)
  end

  @doc """
  Returns a list of valid IANA timezone identifiers for validation.
  Tries to use TzExtra.time_zone_ids() for comprehensive validation,
  falls back to a curated list of common timezones if TzExtra is unavailable.
  """
  def get_valid_timezones do
    try do
      TzExtra.time_zone_ids()
    rescue
      _ ->
        # Fallback to common timezones if TzExtra is not available
        [
          "UTC",
          "America/New_York",
          "America/Chicago",
          "America/Denver",
          "America/Los_Angeles",
          "America/Toronto",
          "America/Vancouver",
          "Europe/London",
          "Europe/Paris",
          "Europe/Berlin",
          "Europe/Rome",
          "Europe/Madrid",
          "Europe/Amsterdam",
          "Asia/Tokyo",
          "Asia/Shanghai",
          "Asia/Hong_Kong",
          "Asia/Singapore",
          "Australia/Sydney",
          "Australia/Melbourne",
          "Pacific/Auckland",
          "Africa/Cairo",
          "Africa/Johannesburg"
        ]
    end
  end
end
