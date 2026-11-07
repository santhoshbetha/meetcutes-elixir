defmodule MeetcutesWeb.AdminController do
  @moduledoc """
  Secure command surface for the MCP administrative tool.

  The route is protected by `MeetcutesWeb.Plugs.McpAdminAuth` and deliberately
  does not use a user bearer token. Database mutations are wrapped in
  `Repo.transaction/1` so a partial administrative update cannot be committed.
  """

  use MeetcutesWeb, :controller

  import Ecto.Query

  alias Meetcutes.Repo
  alias Meetcutes.Accounts.{User, UserToken}
  alias Meetcutes.Events.Event
  alias Meetcutes.Matching
  alias Meetcutes.Notifications

  @valid_states ~w(active inactive suspended delete deleted locked)

  def mcp_action(conn, payload) when is_map(payload) do
    action = payload["action"]
    params = action_params(payload)

    case action do
      "get_system_stats" -> system_stats(conn)
      "toggle_maintenance" -> toggle_flag(conn, :maintenance_mode_active, params)
      "toggle_paywall" -> toggle_flag(conn, :payment_feature_enabled, params)
      "update_user_status" -> update_user_status(conn, params)
      "force_match_count" -> force_match_count(conn, params)
      "push_notification" -> push_notification(conn, params)
      "set_global_announcement" -> set_global_announcement(conn, params)
      _ -> error(conn, :unprocessable_entity, "Unsupported MCP action.")
    end
  end

  def mcp_action(conn, _payload) do
    error(conn, :bad_request, "Expected a JSON command payload.")
  end

  defp system_stats(conn) do
    now = DateTime.utc_now()

    result =
      Repo.transaction(fn ->
        active_users =
          Repo.aggregate(
            from(u in User,
              where:
                u.is_active == true and u.user_state == :active and
                  is_nil(u.deleted_at)
            ),
            :count,
            :id
          )

        event_total = Repo.aggregate(Event, :count, :id)

        active_subscriptions =
          Repo.aggregate(
            from(u in User,
              where:
                u.subscription_expires_at > ^now and
                  is_nil(u.deleted_at)
            ),
            :count,
            :id
          )

        oban_failure_backlog =
          Repo.aggregate(
            from(j in Oban.Job,
              where: j.state in ["retryable", "discarded"]
            ),
            :count,
            :id
          )

        %{
          active_users: active_users,
          event_total: event_total,
          active_subscriptions: active_subscriptions,
          oban_failure_backlog: oban_failure_backlog,
          generated_at: DateTime.to_iso8601(now)
        }
      end)

    case result do
      {:ok, stats} ->
        json(conn, %{success: true, status: "success", data: stats})

      {:error, reason} ->
        error(conn, :internal_server_error, "Could not read system stats: #{inspect(reason)}")
    end
  end

  defp toggle_flag(conn, key, params) do
    current = Application.get_env(:meetcutes, key, key == :payment_feature_enabled)
    value = parse_boolean(first_present(params, ~w(value enabled active)), not current)

    Application.put_env(:meetcutes, key, value)

    json(conn, %{
      success: true,
      status: "success",
      data: %{key => value}
    })
  end

  defp update_user_status(conn, params) do
    with {:ok, state} <-
           normalize_state(first_present(params, ~w(user_state state status))),
         {:ok, user} <- find_user(params) do
      result =
        Repo.transaction(fn ->
          attrs = state_attrs(state)

          case user
               |> Ecto.Changeset.change(attrs)
               |> Repo.update() do
            {:ok, updated} ->
              if state != :active do
                Repo.delete_all(from(t in UserToken, where: t.user_id == ^user.id))
              end

              updated

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)

      case result do
        {:ok, updated} ->
          json(conn, %{
            success: true,
            status: "success",
            data: %{
              user_id: updated.id,
              email: updated.email,
              user_state: updated.user_state,
              is_active: updated.is_active,
              is_locked: updated.is_locked
            }
          })

        {:error, %Ecto.Changeset{} = changeset} ->
          error(
            conn,
            :unprocessable_entity,
            "Could not update user status: #{inspect(changeset.errors)}"
          )

        {:error, reason} ->
          error(conn, :unprocessable_entity, "Could not update user status: #{inspect(reason)}")
      end
    else
      {:error, :not_found} -> error(conn, :not_found, "User not found.")
      {:error, :invalid_state} -> error(conn, :unprocessable_entity, "Invalid user state.")
    end
  end

  defp force_match_count(conn, params) do
    with {:ok, user} <- find_user(params),
         {:ok, count} <-
           parse_count(first_present(params, ~w(count value around_user_count))) do
      result =
        Repo.transaction(fn ->
          user
          |> Ecto.Changeset.change(%{
            around_user_count: count,
            around_user_count_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.update()
          |> case do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      case result do
        {:ok, updated} ->
          json(conn, %{
            success: true,
            status: "success",
            data: %{
              user_id: updated.id,
              email: updated.email,
              around_user_count: updated.around_user_count
            }
          })

        {:error, reason} ->
          error(conn, :unprocessable_entity, "Could not update match count: #{inspect(reason)}")
      end
    else
      {:error, :not_found} ->
        error(conn, :not_found, "User not found.")

      {:error, :invalid_count} ->
        error(conn, :unprocessable_entity, "Count must be a non-negative integer.")
    end
  end

  defp push_notification(conn, params) do
    scope = first_present(params, ~w(target_scope scope))
    title = normalize_text(first_present(params, ~w(title)))
    body = normalize_text(first_present(params, ~w(body message)))

    with {:ok, scope} <- normalize_scope(scope),
         :ok <- validate_notification_title(title),
         {:ok, user_ids} <- notification_targets(scope, params) do
      result =
        Repo.transaction(fn ->
          entries =
            Notifications.build_admin_broadcasts(user_ids, title, body, %{
              "scope" => scope
            })

          count = Notifications.insert_broadcast_entries(entries)
          {count, entries}
        end)

      case result do
        {:ok, {count, entries}} ->
          Notifications.broadcast_entries(entries)

          json(conn, %{
            success: true,
            status: "success",
            data: %{target_scope: scope, recipients: count}
          })

        {:error, reason} ->
          error(conn, :unprocessable_entity, "Could not insert notifications: #{inspect(reason)}")
      end
    else
      {:error, :invalid_scope} ->
        error(conn, :unprocessable_entity, "Invalid notification target scope.")

      {:error, :missing_title} ->
        error(conn, :unprocessable_entity, "Notification title is required.")

      {:error, :not_found} ->
        error(conn, :not_found, "Target user not found.")

      {:error, :invalid_coordinates} ->
        error(conn, :unprocessable_entity, "Invalid area coordinates or radius.")
    end
  end

  defp set_global_announcement(conn, params) do
    message = normalize_text(first_present(params, ~w(message announcement)))
    Application.put_env(:meetcutes, :global_announcement, message)

    json(conn, %{
      success: true,
      status: "success",
      data: %{message: message}
    })
  end

  defp notification_targets("all", _params) do
    {:ok,
     Repo.all(
       from(u in User,
         where:
           u.is_active == true and u.user_state == :active and
             is_nil(u.deleted_at),
         select: u.id
       )
     )}
  end

  defp notification_targets("user", params) do
    with {:ok, user} <- find_user(params), do: {:ok, [user.id]}
  end

  defp notification_targets("area", params) do
    with {:ok, latitude} <- parse_float(first_present(params, ~w(center_lat lat latitude))),
         {:ok, longitude} <- parse_float(first_present(params, ~w(center_lng lng longitude))),
         {:ok, radius_miles} <-
           parse_float(first_present(params, ~w(radius_miles radius))),
         true <- radius_miles > 0 do
      {:ok, Matching.users_within_radius(latitude, longitude, radius_miles)}
    else
      _ -> {:error, :invalid_coordinates}
    end
  end

  defp notification_targets(_scope, _params), do: {:error, :invalid_scope}

  defp normalize_scope(nil), do: {:error, :invalid_scope}

  defp normalize_scope(scope) when is_binary(scope) do
    case scope |> String.trim() |> String.downcase() do
      "all" -> {:ok, "all"}
      "user" -> {:ok, "user"}
      "area" -> {:ok, "area"}
      _ -> {:error, :invalid_scope}
    end
  end

  defp normalize_scope(_scope), do: {:error, :invalid_scope}

  defp validate_notification_title(title) when is_binary(title) and title != "", do: :ok
  defp validate_notification_title(_title), do: {:error, :missing_title}

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(value) when is_number(value), do: to_string(value)
  defp normalize_text(_value), do: nil

  defp parse_float(value) when is_number(value), do: {:ok, value / 1}

  defp parse_float(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _ -> {:error, :invalid_coordinates}
    end
  end

  defp parse_float(_value), do: {:error, :invalid_coordinates}

  defp state_attrs(:active), do: %{user_state: :active, is_active: true, is_locked: false}
  defp state_attrs(:inactive), do: %{user_state: :inactive, is_active: false, is_locked: false}
  defp state_attrs(:suspended), do: %{user_state: :suspended, is_active: false, is_locked: true}
  defp state_attrs(:delete), do: %{user_state: :delete, is_active: false, is_locked: true}

  defp normalize_state(nil), do: {:error, :invalid_state}

  defp normalize_state(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    cond do
      normalized in @valid_states and normalized in ~w(locked) -> {:ok, :suspended}
      normalized in @valid_states and normalized in ~w(deleted) -> {:ok, :delete}
      normalized in @valid_states -> {:ok, String.to_existing_atom(normalized)}
      true -> {:error, :invalid_state}
    end
  end

  defp normalize_state(_value), do: {:error, :invalid_state}

  defp find_user(params) do
    cond do
      id = first_present(params, ~w(user_id id)) ->
        case Repo.get(User, id) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      handle = first_present(params, ~w(user_handle userhandle handle nickname)) ->
        case Repo.one(
               from(u in User,
                 where: fragment("LOWER(?) = LOWER(?)", u.nickname, ^handle),
                 limit: 1
               )
             ) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      email = first_present(params, ~w(email)) ->
        case Repo.one(
               from(u in User,
                 where: fragment("LOWER(?) = LOWER(?)", u.email, ^email),
                 limit: 1
               )
             ) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      true ->
        {:error, :not_found}
    end
  end

  defp parse_count(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp parse_count(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {count, ""} when count >= 0 -> {:ok, count}
      _ -> {:error, :invalid_count}
    end
  end

  defp parse_count(_value), do: {:error, :invalid_count}

  defp parse_boolean(true, _default), do: true
  defp parse_boolean(false, _default), do: false
  defp parse_boolean(1, _default), do: true
  defp parse_boolean(0, _default), do: false

  defp parse_boolean(value, default) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      value when value in ~w(true 1 yes on) -> true
      value when value in ~w(false 0 no off) -> false
      _ -> default
    end
  end

  defp parse_boolean(_value, default), do: default

  defp action_params(%{"params" => %{} = params}), do: params
  defp action_params(payload), do: payload

  defp first_present(map, keys) when is_map(map) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.fetch(map, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end

  defp error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{success: false, status: "error", message: message})
  end
end
