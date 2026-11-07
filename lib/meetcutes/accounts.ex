defmodule Meetcutes.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Meetcutes.Repo

  require Logger

  alias Meetcutes.Accounts.{User, UserToken, UserNotifier}
  alias Meetcutes.Relationships

  # Maximum number of reset-link requests allowed before support must intervene.
  @password_reset_limit 6

  @doc """
  Returns the maximum number of password reset requests allowed per account.
  """
  def password_reset_limit, do: @password_reset_limit

  @doc """
  Returns the configured frontend URL used to build links inside emails.

  The value comes from `config :meetcutes, Meetcutes.Accounts, frontend_url: ...`
  and falls back to the local Vite dev server.
  """
  def frontend_url do
    :meetcutes
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:frontend_url, "http://localhost:5173")
    |> String.trim_trailing("/")
  end

  @doc """
  Builds the React confirmation link for an email-change token.

  The link points at `/auth/confirm` with `type=email_change` so the same page
  that handles password recovery can also confirm an email change.
  """
  def email_change_url(token) do
    query = URI.encode_query([{"type", "email_change"}, {"token", token}])
    "#{frontend_url()}/auth/confirm?#{query}"
  end

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    from(u in User, where: u.email == ^email and is_nil(u.deleted_at)) |> Repo.one()
  end

  @doc """
  Gets a user by phone number.

  ## Examples

      iex> get_user_by_phone_number("+1234567890")
      %User{}

      iex> get_user_by_phone_number("unknown")
      nil

  """
  def get_user_by_phone_number(phone_number) when is_binary(phone_number) do
    from(u in User, where: u.phone_number == ^phone_number and is_nil(u.deleted_at)) |> Repo.one()
  end

  @doc """
  Gets a user by nickname.

  ## Examples

      iex> get_user_by_nickname("johndoe")
      %User{}

      iex> get_user_by_nickname("unknown")
      nil

  """
  def get_user_by_nickname(nickname) when is_binary(nickname) do
    from(u in User,
      where:
        fragment("lower(?) = lower(?)", u.nickname, ^nickname) and
          is_nil(u.deleted_at)
    )
    |> Repo.one()
  end

  @doc """
  Case-insensitive handle availability check.

  When `excluding_user_id` is supplied, that account's current handle is
  ignored so a user can keep the handle they already own.
  """
  def handle_taken?(handle, excluding_user_id \\ nil) when is_binary(handle) do
    query =
      from(u in User,
        where:
          fragment("lower(?) = lower(?)", u.nickname, ^handle) and
            is_nil(u.deleted_at)
      )

    query =
      if is_binary(excluding_user_id) do
        from(u in query, where: u.id != ^excluding_user_id)
      else
        query
      end

    Repo.exists?(query)
  end

  def search_users(search_term) when is_binary(search_term) and search_term != "" do
    search_users(query: search_term)
  end

  @doc """
  Searches for users with advanced filtering options.

  ## Options
  - :query - Search term for email, phone, or nickname
  - :latitude - Search origin latitude for nearby matching (optional)
  - :longitude - Search origin longitude for nearby matching (optional)
  - :distance_miles - Search radius in miles for nearby matching (optional)
  - :gender - Explicit gender filter (optional fallback)
  - :viewer_gender - Authenticated requester's gender; when Male/Female the
    discovery feed is strictly scoped to the opposite gender
  - :age_from - Minimum age (optional)
  - :age_to - Maximum age (optional)
  - :viewer_id - Exclude the viewer and anyone blocked/muted by either party
  - :limit - Maximum number of rows to return (optional)
  - :offset - Number of rows to skip (optional)
  """
  def search_users(opts) when is_list(opts) do
    query = Keyword.get(opts, :query, "")
    latitude = Keyword.get(opts, :latitude)
    longitude = Keyword.get(opts, :longitude)
    distance_miles = Keyword.get(opts, :distance_miles)
    gender = Keyword.get(opts, :gender)
    viewer_gender = Keyword.get(opts, :viewer_gender)
    age_from = Keyword.get(opts, :age_from)
    age_to = Keyword.get(opts, :age_to)
    viewer_id = Keyword.get(opts, :viewer_id)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    base_query =
      from(u in User,
        where: u.is_active == true and u.is_approved == true and is_nil(u.deleted_at)
      )

    # Apply text search if query provided
    query_with_search =
      if query != "" and query != nil do
        from(u in base_query,
          where:
            u.email == ^query or
              u.phone_number == ^query or
              u.nickname == ^query
        )
      else
        base_query
      end

    # Apply the discovery gender scope. Authenticated Male/Female viewers are
    # strictly restricted to the opposite gender; the explicit `gender` option
    # remains as a fallback for non-binary/unspecified viewers or direct callers.
    query_with_gender =
      case opposite_gender(viewer_gender) do
        nil ->
          if gender do
            from(u in query_with_search, where: u.gender == ^gender)
          else
            query_with_search
          end

        opposite ->
          from(u in query_with_search, where: u.gender == ^opposite)
      end

    # Apply age range filters
    query_with_age = query_with_gender

    query_with_age =
      if age_from do
        from(u in query_with_age, where: u.age >= ^age_from)
      else
        query_with_age
      end

    query_with_age =
      if age_to do
        from(u in query_with_age, where: u.age <= ^age_to)
      else
        query_with_age
      end

    query_with_distance =
      if is_number(latitude) and is_number(longitude) and is_number(distance_miles) do
        prefixes = nearby_geohash_prefixes(latitude, longitude, distance_miles)

        from(u in query_with_age,
          where: not is_nil(u.geohash),
          where:
            fragment(
              "EXISTS (SELECT 1 FROM unnest(?::text[]) AS p WHERE ? LIKE p || '%')",
              ^prefixes,
              u.geohash
            )
        )
      else
        query_with_age
      end

    # "events-only" profiles do not appear in the online people feed.
    query_with_visibility =
      from(u in query_with_distance,
        where:
          fragment(
            "COALESCE(?->>'visibility_preference', 'both') <> 'events-only'",
            u.settings
          )
      )

    query_with_viewer =
      if viewer_id do
        from(u in query_with_visibility, where: u.id != ^viewer_id)
        |> Relationships.exclude_hidden(viewer_id)
      else
        query_with_visibility
      end

    query_with_order =
      from(u in query_with_viewer,
        order_by: [desc: u.last_active_at, desc: u.inserted_at]
      )

    query_with_pagination =
      if is_integer(limit) and limit > 0 do
        from(u in query_with_order, limit: ^limit, offset: ^offset)
      else
        query_with_order
      end

    Repo.all(query_with_pagination)
  end

  def search_users(_), do: []

  # The core discovery feed is a straight dating matrix: Male viewers only see
  # Female profiles and vice versa. Unknown/unspecified genders fall through to
  # the optional explicit :gender filter.
  defp opposite_gender(gender) when is_binary(gender) do
    case String.downcase(String.trim(gender)) do
      "male" -> "Female"
      "female" -> "Male"
      _other -> nil
    end
  end

  defp opposite_gender(_gender), do: nil

  defp nearby_geohash_prefixes(latitude, longitude, radius_in_miles) do
    precision = precision_for_miles(radius_in_miles)
    center_hash = Geohash.encode(latitude, longitude, 9)
    neighbors = Geohash.neighbors(center_hash)

    [center_hash | Map.values(neighbors)]
    |> Enum.map(&String.slice(&1, 0, precision))
    |> Enum.uniq()
  end

  defp precision_for_miles(radius_in_miles) when radius_in_miles <= 20, do: 4
  defp precision_for_miles(_radius_in_miles), do: 3

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = from(u in User, where: u.email == ^email and is_nil(u.deleted_at)) |> Repo.one()
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> nil
      user -> if user.deleted_at, do: nil, else: user
    end
  end

  @doc """
  Gets a single user by ID, raising if not found.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Returns every user matching the given IDs in a single query.

  Used by event serialization to decorate attendee IDs without an N+1 query
  per attendee. Unknown or deleted IDs are simply omitted.
  """
  def list_users_by_ids([]), do: []

  def list_users_by_ids(ids) when is_list(ids) do
    User
    |> where([u], u.id in ^ids and is_nil(u.deleted_at))
    |> Repo.all()
  end

  @doc """
  Gets user data by user ID with specific fields.

  Returns a map with selected user information or nil if user doesn't exist.

  ## Examples

      iex> get_user_data("user-id-123")
      %{userid: "user-id-123", nickname: "johndoe", ...}

      iex> get_user_data("nonexistent-id")
      nil

  """
  def get_user_data(user_id) when is_binary(user_id) do
    case Repo.get(User, user_id) do
      nil ->
        nil

      user ->
        %{
          userid: user.id,
          nickname: user.nickname,
          first_name: user.first_name,
          age: user.age,
          gender: user.gender,
          city: user.city,
          state: user.state,
          phone_number: user.phone_number,
          email: user.email,
          bio: user.bio,
          facebook: user.facebook,
          instagram: user.instagram,
          linkedin: user.linkedin,
          questionaire_values: user.questionaire_values,
          questionaire_values_set: user.questionaire_values_set,
          time_of_login: user.time_of_login,
          user_state: user.user_state,
          id_verified: user.id_verified,
          terms_accepted: user.terms_accepted
        }
    end
  end

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Ecto.Changeset.put_change(:calendar_token, generate_calendar_token())
    |> Repo.insert()
  end

  defp generate_calendar_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Meetcutes.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Confirms an email change from an emailed token without requiring a session.

  The token itself is the credential. It is looked up by its hashed value, the
  owning user is loaded, and `update_user_email/2` still enforces the
  current-email context and the token expiry window. The token is deleted on
  success, so a link can only be used once.
  """
  def confirm_email_change(token) when is_binary(token) do
    with {:ok, hashed_token} <- UserToken.hash_session_token(token),
         %UserToken{user_id: user_id, context: "change:" <> _} <-
           Repo.one(from t in UserToken, where: t.token == ^hashed_token),
         %User{} = user <- Repo.get(User, user_id),
         {:ok, %User{} = user} <- update_user_email(user, token) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  def confirm_email_change(_token), do: :error

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Meetcutes.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:tokens_to_expire, fn _repo, _changes ->
      {:ok, Repo.all_by(UserToken, user_id: user.id)}
    end)
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, tokens_to_expire: tokens}} -> {:ok, {user, tokens}}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a user by setting the deleted_at timestamp (soft delete).

  This also deletes all user images from storage.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    # Delete all user images first
    Meetcutes.ImageUploader.delete_all_user_images(user)

    # Soft delete the user by setting deleted_at
    user
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
    |> Repo.update()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Marks a successful sign-in and refreshes all presence-facing timestamps.
  """
  def record_login(%User{} = user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    active_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    user
    |> Ecto.Changeset.change(
      time_of_login: now,
      last_login_at: now,
      last_seen_at: now,
      last_active_at: active_now
    )
    |> Repo.update()
    |> case do
      {:ok, updated} -> updated
      {:error, _changeset} -> user
    end
  end

  @doc """
  Refreshes a user's last-seen timestamps during token validation or a socket
  handshake. Writes are throttled to once per minute per user.
  """
  def touch_last_seen(%User{} = user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    active_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    cutoff = DateTime.add(now, -60, :second)

    Repo.update_all(
      from(u in User,
        where:
          u.id == ^user.id and
            (is_nil(u.last_seen_at) or u.last_seen_at < ^cutoff)
      ),
      set: [last_seen_at: now, last_active_at: active_now]
    )

    :ok
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    case UserToken.verify_session_token_query(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    case UserToken.verify_magic_link_token_query(token) do
      {:ok, query} ->
        do_login_user_by_magic_link(query)

      :error ->
        {:error, :not_found}
    end
  end

  defp do_login_user_by_magic_link(query) do
    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    case UserToken.hash_session_token(token) do
      {:ok, hashed_token} ->
        Repo.delete_all(from(UserToken, where: [token: ^hashed_token, context: "session"]))
        :ok

      :error ->
        :ok
    end
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.is_confirmed do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.update_all(
      :reset_password_attempts,
      from(u in User, where: u.id == ^user.id),
      set: [password_retry_count: 0, password_reset_pending: false]
    )
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Atomically increments the password reset request counter for a user.

  The increment happens in PostgreSQL (`COALESCE + 1`) so concurrent reset
  requests can never race and overwrite each other. Returns the resulting
  counter value.
  """
  def record_password_reset_attempt(%User{} = user) do
    Repo.update_all(
      from(u in User,
        where: u.id == ^user.id,
        update: [
          set: [
            password_retry_count: fragment("COALESCE(?, 0) + 1", u.password_retry_count),
            password_reset_pending: true
          ]
        ]
      ),
      []
    )

    case Repo.one(from u in User, where: u.id == ^user.id, select: u.password_retry_count) do
      nil -> 0
      count -> count
    end
  end

  @doc """
  Returns true when an account has exhausted its password reset allowance.
  """
  def password_reset_limit_exceeded?(count) when is_integer(count),
    do: count > @password_reset_limit

  def password_reset_limit_exceeded?(_count), do: false

  @doc """
  Sends a password reset email to the user with the given email address.

  ## Examples

      iex> reset_password_for_email("user@example.com", fn token -> "https://example.com/reset/\#{token}" end)
      {:ok, %{to: ..., body: ...}}

      iex> reset_password_for_email("nonexistent@example.com", fn token -> "https://example.com/reset/\#{token}" end)
      {:error, :user_not_found}

  """
  def reset_password_for_email(email, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    case get_user_by_email(email) do
      nil ->
        {:error, :user_not_found}

      user ->
        deliver_user_reset_password_instructions(user, reset_password_url_fun)
    end
  end

  @doc """
  Updates a user with the given attributes.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a user's nickname, checking for uniqueness.

  ## Examples

      iex> update_user_nickname(user, "newnickname")
      {:ok, %User{}}

      iex> update_user_nickname(user, "taken_nickname")
      {:error, :nickname_taken}

  """
  def update_user_nickname(%User{} = user, nickname)
      when is_binary(nickname) and nickname != "" do
    # Check if nickname is already taken by another user
    case Repo.get_by(User, nickname: nickname) do
      nil ->
        # Nickname is available
        update_user(user, %{nickname: nickname})

      %User{id: existing_user_id} ->
        # Check if it's the same user (no change needed)
        if existing_user_id == user.id do
          {:ok, user}
        else
          {:error, :nickname_taken}
        end
    end
  end

  def update_user_nickname(_user, _nickname), do: {:error, :invalid_nickname}

  @doc """
  Updates a user's last_seen_at timestamp.

  ## Examples

      iex> update_user_last_seen(user_id)
      {:ok, %User{}}

  """
  def update_user_last_seen(user_id) do
    case get_user(user_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        update_user(user, %{last_seen_at: DateTime.utc_now()})
    end
  end

  @doc """
  Checks if an email is available for use (not taken by another user).

  ## Examples

      iex> email_available?("new@example.com")
      true

      iex> email_available?("existing@example.com")
      false

  """
  def email_available?(email) when is_binary(email) and email != "" do
    Repo.get_by(User, email: email) == nil
  end

  def email_available?(_), do: false

  @doc """
  Checks if a phone number is available for use (not taken by another user).

  ## Examples

      iex> phone_number_available?("+1234567890")
      true

      iex> phone_number_available?("+0987654321")
      false

  """
  def phone_number_available?(phone_number) when is_binary(phone_number) and phone_number != "" do
    Repo.get_by(User, phone_number: phone_number) == nil
  end

  def phone_number_available?(_), do: false

  @doc """
  Updates a user's email directly, checking for uniqueness.

  ## Examples

      iex> update_user_email_direct(user, "new@example.com")
      {:ok, %User{}}

      iex> update_user_email_direct(user, "taken@example.com")
      {:error, :email_taken}

  """
  def update_user_email_direct(%User{} = user, email) when is_binary(email) and email != "" do
    # Check if email is already taken by another user
    case Repo.get_by(User, email: email) do
      nil ->
        # Email is available
        update_user(user, %{email: email})

      %User{id: existing_user_id} ->
        # Check if it's the same user (no change needed)
        if existing_user_id == user.id do
          {:ok, user}
        else
          {:error, :email_taken}
        end
    end
  end

  def update_user_email_direct(_user, _email), do: {:error, :invalid_email}

  @doc """
  Updates a user's phone number, checking for uniqueness.

  ## Examples

      iex> update_user_phone_number(user, "+1234567890")
      {:ok, %User{}}

      iex> update_user_phone_number(user, "+0987654321")
      {:error, :phone_number_taken}

  """
  def update_user_phone_number(%User{} = user, phone_number)
      when is_binary(phone_number) and phone_number != "" do
    # Check if phone number is already taken by another user
    case Repo.get_by(User, phone_number: phone_number) do
      nil ->
        # Phone number is available
        update_user(user, %{phone_number: phone_number})

      %User{id: existing_user_id} ->
        # Check if it's the same user (no change needed)
        if existing_user_id == user.id do
          {:ok, user}
        else
          {:error, :phone_number_taken}
        end
    end
  end

  def update_user_phone_number(_user, _phone_number), do: {:error, :invalid_phone_number}

  @doc """
  Soft deletes a user by setting deleted_at timestamp.

  ## Examples

      iex> soft_delete_user(user)
      {:ok, %User{}}

      iex> soft_delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def soft_delete_user(%User{} = user) do
    update_user(user, %{deleted_at: DateTime.utc_now()})
  end

  @doc """
  Restores a soft-deleted user by clearing deleted_at.

  ## Examples

      iex> restore_user(user)
      {:ok, %User{}}

      iex> restore_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def restore_user(%User{} = user) do
    update_user(user, %{deleted_at: nil})
  end

  @doc """
  Hard deletes a user permanently from the database.

  ## Examples

      iex> hard_delete_user(user)
      {:ok, %User{}}

      iex> hard_delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def hard_delete_user(%User{} = user) do
    # Delete user's images before deleting the user
    delete_user_images(user)

    Repo.delete(user)
  end

  @doc """
  Deletes images for users who have been soft-deleted for more than 30 days.
  """
  def delete_soft_deleted_users_images do
    # Find users soft-deleted more than 30 days ago
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

    soft_deleted_users =
      User
      |> where([u], not is_nil(u.deleted_at))
      |> where([u], u.deleted_at < ^thirty_days_ago)
      |> Repo.all()

    # Delete images for each user
    Enum.each(soft_deleted_users, &delete_user_images/1)

    {:ok, length(soft_deleted_users)}
  rescue
    error ->
      Logger.error("Error during soft-deleted users images cleanup: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Deletes all images associated with a user.

  This includes avatar images and any other uploaded images.
  """
  def delete_user_images(%User{} = user) do
    # Delete avatar if it exists
    if user.avatar do
      delete_avatar_image(user)
    end

    # Delete all uploaded images for this user from S3
    delete_all_user_images_from_s3(user)
  end

  defp delete_avatar_image(%User{} = user) do
    # If avatar is stored as a URL or filename, delete it using Waffle
    case user.avatar do
      %{"filename" => filename} when is_binary(filename) ->
        Meetcutes.ImageUploader.delete({filename, user})

      %{"url" => url} when is_binary(url) ->
        # Extract filename from URL if needed
        # For now, skip URL-based deletion as it's complex
        :ok

      _ ->
        :ok
    end
  end

  defp delete_all_user_images_from_s3(%User{} = user) do
    bucket = System.get_env("AWS_S3_BUCKET")

    if bucket do
      prefix = "users/#{user.id}/"

      # List all objects with the prefix
      case ExAws.S3.list_objects_v2(bucket, prefix: prefix) |> ExAws.request() do
        {:ok, %{body: %{contents: objects}}} when is_list(objects) ->
          # Delete all objects in batches (S3 allows max 1000 objects per delete request)
          objects
          |> Enum.map(& &1.key)
          |> Enum.chunk_every(1000)
          |> Enum.each(fn object_keys ->
            ExAws.S3.delete_all_objects(bucket, object_keys) |> ExAws.request()
          end)

          Logger.info("Deleted #{length(objects)} images for user #{user.id}")

        {:ok, %{body: %{contents: nil}}} ->
          # No objects found
          Logger.info("No images found for user #{user.id}")

        {:error, error} ->
          Logger.error("Failed to list user #{user.id} images for deletion: #{inspect(error)}")
      end
    else
      Logger.warning("AWS_S3_BUCKET not configured, skipping image cleanup for user #{user.id}")
    end

    :ok
  end

  @doc """
  Checks if a user is soft-deleted.

  ## Examples

      iex> user_deleted?(user)
      true

  """
  def user_deleted?(%User{deleted_at: deleted_at}) when not is_nil(deleted_at), do: true
  def user_deleted?(_), do: false

  @doc """
  Updates user's location (city and state) with monthly limit check.

  ## Examples

      iex> update_user_location(user, %{city: "New York", state: "NY"})
      {:ok, %User{}}

      iex> update_user_location(user, %{city: "Boston", state: "MA"})
      {:error, :location_change_limit_exceeded}

  """
  def update_user_location(%User{} = user, attrs) do
    # Check if location was changed within the last month
    if user.date_of_location do
      last_change = DateTime.to_date(user.date_of_location)
      today = Date.utc_today()
      days_since_change = Date.diff(today, last_change)

      if days_since_change < 30 do
        {:error, :location_change_limit_exceeded}
      else
        do_update_location(user, attrs)
      end
    else
      # No previous change, allow update
      do_update_location(user, attrs)
    end
  end

  defp do_update_location(user, attrs) do
    location_attrs = Map.take(attrs, ["city", "state"])
    location_attrs = Map.put(location_attrs, "date_of_location", DateTime.utc_now())

    # Reset geo data when location changes
    reset_attrs = %{
      "latitude" => nil,
      "longitude" => nil,
      "default_coords_set" => false,
      "user_coords_set" => false,
      "exact_coords_set" => false,
      "date_of_coordinates" => nil
    }

    update_attrs = Map.merge(location_attrs, reset_attrs)

    update_user(user, update_attrs)
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Updates user's geo coordinates (latitude and longitude).

  ## Examples

      iex> update_user_coordinates(user, %{latitude: 40.7128, longitude: -74.0060})
      {:ok, %User{}}

      iex> update_user_coordinates(user, %{latitude: 42.3601, longitude: -71.0589})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_coordinates(%User{} = user, attrs) do
    coords_attrs = Map.take(attrs, ["latitude", "longitude"])
    coords_attrs = Map.put(coords_attrs, "date_of_coordinates", DateTime.utc_now())

    # Determine coordinate flags based on what's being set
    flags = %{}

    flags =
      if Map.has_key?(coords_attrs, "latitude") and Map.has_key?(coords_attrs, "longitude") do
        Map.put(flags, "user_coords_set", true)
      else
        flags
      end

    update_attrs = Map.merge(coords_attrs, flags)

    update_user(user, update_attrs)
  end

  @doc """
  Checks if user can change location (not within last 30 days).

  ## Examples

      iex> can_change_location?(user)
      true

  """
  def can_change_location?(%User{date_of_location: nil}), do: true

  def can_change_location?(%User{date_of_location: date_of_location}) do
    last_change = DateTime.to_date(date_of_location)
    today = Date.utc_today()
    days_since_change = Date.diff(today, last_change)
    days_since_change >= 30
  end

  @doc """
  Gets days remaining until user can change location again.

  ## Examples

      iex> days_until_location_change(user)
      15

  """
  def days_until_location_change(%User{date_of_location: nil}), do: 0

  def days_until_location_change(%User{date_of_location: date_of_location}) do
    last_change = DateTime.to_date(date_of_location)
    today = Date.utc_today()
    days_since_change = Date.diff(today, last_change)
    max(0, 30 - days_since_change)
  end

  @doc """
  Generates a websocket authentication token for a user.

  ## Examples

      iex> generate_websocket_token(user)
      "sfMyNTY.g_bg.l2V3..."

  """
  def generate_websocket_token(%User{} = user) do
    Phoenix.Token.sign(MeetcutesWeb.Endpoint, "user socket", user.id)
  end

  def get_user_by_calendar_token!(token) do
    # 2026 Security: Ensure your DB has a unique_index on :calendar_token
    Repo.get_by!(User, calendar_token: token)
  end

  def update_user_profile(user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end
end
