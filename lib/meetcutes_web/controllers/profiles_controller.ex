defmodule MeetcutesWeb.ProfilesController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Accounts
  alias Meetcutes.Matching
  alias Meetcutes.Profiles
  alias Meetcutes.Relationships
  alias MeetcutesWeb.UserJSON

  action_fallback MeetcutesWeb.FallbackController

  @handle_regex ~r/^[A-Za-z][A-Za-z0-9_]{4,14}$/

  @doc """
  GET /api/v1/profiles/me
  """
  def me(conn, _params) do
    user = conn.assigns.current_user
    user = Matching.refresh_if_stale(user)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: %{profile: UserJSON.profile(user)}
    })
  end

  @doc """
  GET /api/v1/profiles/:id

  Returns a public profile unless either party has blocked the other. Muted
  profiles remain reachable so they can be inspected and unmuted from the
  management directory.
  """
  def show(conn, %{"id" => id}) do
    viewer = conn.assigns.current_user

    cond do
      id == viewer.id ->
        me(conn, %{})

      Relationships.blocked?(viewer.id, id) ->
        hidden(conn)

      true ->
        case Accounts.get_user(id) do
          %{is_active: true, is_approved: true} = user ->
            conn
            |> put_status(:ok)
            |> json(%{status: "success", data: %{profile: UserJSON.public_profile(user)}})

          _ ->
            hidden(conn)
        end
    end
  end

  @doc """
  PATCH /api/v1/profiles/me

  Accepts JSON or multipart form data. `avatar` and `banner` file parts are
  validated by magic bytes before anything is written.
  """
  def update(conn, params) do
    user = conn.assigns.current_user
    {attrs, opts} = extract_params(params)

    case Profiles.update_profile(user, attrs, opts) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Profile updated successfully",
          data: %{profile: UserJSON.profile(updated_user)}
        })

      {:error, reason} ->
        handle_error(conn, reason)
    end
  end

  @doc """
  DELETE /api/v1/profiles/me

  Soft-deactivates the authenticated account and revokes its sessions.
  """
  def deactivate(conn, _params) do
    user = conn.assigns.current_user

    case Profiles.deactivate_profile(user) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Account deactivated successfully"})

      {:error, reason} ->
        handle_error(conn, reason)
    end
  end

  @doc """
  POST /api/v1/profiles/me/images

  Stores a profile photo in a 0-based slot (`0`..`9`). Accepts multipart form
  data with `slot` and a `file` (or `image`) part.
  """
  def upload_image(conn, params) do
    user = conn.assigns.current_user

    with {:ok, slot} <- parse_slot(Map.get(params, "slot")),
         {:ok, upload} <- upload_param(params),
         {:ok, updated} <- Profiles.set_image(user, slot, upload) do
      conn
      |> put_status(:ok)
      |> json(%{
        status: "success",
        message: "Profile image uploaded successfully",
        data: %{profile: UserJSON.profile(updated)}
      })
    else
      {:error, reason} -> handle_error(conn, reason)
    end
  end

  @doc """
  DELETE /api/v1/profiles/me/images/:slot

  Clears a 0-based photo slot and removes the stored file.
  """
  def delete_image(conn, %{"slot" => slot}) do
    user = conn.assigns.current_user

    with {:ok, slot} <- parse_slot(slot),
         {:ok, updated} <- Profiles.remove_image(user, slot) do
      conn
      |> put_status(:ok)
      |> json(%{
        status: "success",
        message: "Profile image removed successfully",
        data: %{profile: UserJSON.profile(updated)}
      })
    else
      {:error, reason} -> handle_error(conn, reason)
    end
  end

  @doc """
  PUT /api/v1/profiles/me/images

  Reorders the user's existing photos. The payload may only reference files the
  account already owns, so it cannot be used to attach arbitrary paths.
  """
  def reorder_images(conn, params) do
    user = conn.assigns.current_user

    with {:ok, images} <- images_param(params),
         {:ok, updated} <- Profiles.reorder_images(user, images) do
      conn
      |> put_status(:ok)
      |> json(%{
        status: "success",
        message: "Profile images updated successfully",
        data: %{profile: UserJSON.profile(updated)}
      })
    else
      {:error, reason} -> handle_error(conn, reason)
    end
  end

  @doc """
  GET /api/v1/users/check-handle?handle=:handle

  Case-insensitive global handle availability check.
  """
  def check_handle(conn, params) do
    handle = normalize_handle(params["handle"])

    conn
    |> put_status(:ok)
    |> json(%{
      available: Regex.match?(@handle_regex, handle) and Profiles.handle_available?(handle)
    })
  end

  @doc """
  PATCH /api/v1/users/me/set-handle

  Commits a validated, globally unique handle to the bearer user.
  """
  def set_handle(conn, params) do
    user = conn.assigns.current_user
    handle = normalize_handle(params["handle"] || get_in(params, ["user", "handle"]))

    cond do
      not Regex.match?(@handle_regex, handle) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          code: "invalid_handle",
          available: false,
          message:
            "Handle must be 5-15 characters, start with a letter, and contain only letters, numbers, or underscores."
        })

      Accounts.handle_taken?(handle, user.id) ->
        conn
        |> put_status(:conflict)
        |> json(%{
          status: "error",
          code: "handle_taken",
          available: false,
          message: "This handle is already taken."
        })

      true ->
        case Accounts.update_user(user, %{nickname: handle}) do
          {:ok, updated} ->
            conn
            |> put_status(:ok)
            |> json(%{
              status: "success",
              message: "Handle assigned successfully",
              data: %{profile: UserJSON.profile(updated)}
            })

          {:error, %Ecto.Changeset{} = changeset} ->
            if changeset.errors[:nickname] do
              conn
              |> put_status(:conflict)
              |> json(%{
                status: "error",
                code: "handle_taken",
                available: false,
                message: "This handle is already taken."
              })
            else
              errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

              conn
              |> put_status(:unprocessable_entity)
              |> json(%{status: "error", message: "Validation failed", errors: errors})
            end
        end
    end
  end

  defp normalize_handle(value) when is_binary(value), do: String.trim(value)
  defp normalize_handle(_value), do: ""

  @doc """
  GET /api/v1/profiles/handle_available/:handle

  Reports whether a nickname can still be claimed. Never reveals any account
  details beyond availability.
  """
  def handle_available(conn, %{"handle" => handle}) do
    available = Profiles.handle_available?(handle)

    conn
    |> put_status(:ok)
    |> json(%{
      status: "success",
      data: %{handle: handle, available: available, taken: not available}
    })
  end

  # A profile photo endpoint writes exactly one file into exactly one slot.
  # Reject list payloads instead of silently picking one so a client can never
  # exceed the ten-photo limit by bundling multiple uploads in one request.
  defp upload_param(params) do
    uploads =
      ["file", "image", "files", "images"]
      |> Enum.flat_map(fn key ->
        case Map.get(params, key) do
          %Plug.Upload{} = upload -> [upload]
          list when is_list(list) -> Enum.filter(list, &match?(%Plug.Upload{}, &1))
          _ -> []
        end
      end)

    case uploads do
      [upload] -> {:ok, upload}
      [] -> {:error, :invalid_image}
      _many -> {:error, :multiple_files_not_supported}
    end
  end

  defp parse_slot(value) when is_integer(value), do: {:ok, value}

  defp parse_slot(value) when is_binary(value) do
    case Integer.parse(value) do
      {slot, ""} -> {:ok, slot}
      _ -> {:error, :invalid_slot}
    end
  end

  defp parse_slot(_value), do: {:error, :invalid_slot}

  defp images_param(%{"images" => images}) when is_list(images), do: {:ok, images}

  defp images_param(%{"images" => images}) when is_binary(images) do
    case Jason.decode(images) do
      {:ok, decoded} when is_list(decoded) -> {:ok, decoded}
      _ -> {:error, :invalid_images}
    end
  end

  defp images_param(_params), do: {:error, :invalid_images}

  defp extract_params(params) do
    opts = [
      avatar: upload(params["avatar"]),
      banner: upload(params["banner"])
    ]

    attrs =
      cond do
        is_map(params["profile"]) -> params["profile"]
        is_binary(params["profile"]) -> decode_map(params["profile"], params)
        is_map(params["user"]) -> params["user"]
        true -> Map.drop(params, ["avatar", "banner"])
      end

    {attrs, opts}
  end

  defp decode_map(value, fallback) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> Map.drop(fallback, ["avatar", "banner", "profile"])
    end
  end

  defp upload(%Plug.Upload{} = upload), do: upload
  defp upload(_value), do: nil

  defp handle_error(conn, %Ecto.Changeset{} = changeset) do
    MeetcutesWeb.FallbackController.call(conn, {:error, changeset})
  end

  defp handle_error(conn, reason),
    do: MeetcutesWeb.FallbackController.call(conn, {:error, reason})

  defp hidden(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{
      status: "error",
      message: "Profile not found",
      errors: ["The requested profile is not available."]
    })
  end
end
