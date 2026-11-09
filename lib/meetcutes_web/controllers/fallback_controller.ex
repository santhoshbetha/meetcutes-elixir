defmodule MeetcutesWeb.FallbackController do
  use MeetcutesWeb, :controller

  # 1. DATABASE VALIDATION ERRORS (422)
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors = changeset_errors(changeset)

    detail =
      errors
      |> Enum.flat_map(fn {field, messages} ->
        Enum.map(messages, &"#{field} #{&1}")
      end)
      |> Enum.join("; ")

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      success: false,
      message: "Validation failed",
      msg: "Validation failed: #{detail}",
      errors: errors
    })
  end

  # 2. ENTITY NOT FOUND LOOKUPS (404)
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{
      status: "error",
      message: "Resource lookup failed",
      errors: ["The requested resource could not be found."]
    })
  end

  def call(conn, {:error, :target_not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{
      status: "error",
      message: "Resource lookup failed",
      errors: ["The requested user could not be found."]
    })
  end

  def call(conn, {:error, :event_not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{
      status: "error",
      message: "Event not found",
      errors: ["The requested event could not be found."]
    })
  end

  def call(conn, {:error, :conflict}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      status: "error",
      code: "conflict",
      message: "Another event already occupies this location at that time",
      errors: %{time: ["conflicts with an existing event at this location"]}
    })
  end

  def call(conn, {:error, :too_far}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      code: "too_far",
      message: "Event location must be within 150 miles of your location",
      errors: %{location: ["must be within 150 miles of your location"]}
    })
  end

  def call(conn, {:error, :invalid_time_range}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      message: "Validation failed",
      errors: %{end_time: ["must be after start time"]}
    })
  end

  def call(conn, {:error, :already_attending}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      code: "already_attending",
      message: "You are already attending this event",
      errors: %{event: ["already joined"]}
    })
  end

  def call(conn, {:error, :not_attending}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      code: "not_attending",
      message: "You are not attending this event",
      errors: %{event: ["not joined"]}
    })
  end

  # 3. RELATIONSHIP / UPLOAD BUSINESS RULES
  def call(conn, {:error, :invalid_image}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      message: "Validation failed",
      errors: %{image: ["must be a JPEG, PNG, GIF, or WebP image"]}
    })
  end

  def call(conn, {:error, :image_too_large}) do
    conn
    |> put_status(:request_entity_too_large)
    |> json(%{
      status: "error",
      message: "Uploaded file is too large",
      errors: %{image: ["must be smaller than the upload limit"]}
    })
  end

  def call(conn, {:error, :empty_file}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      message: "Validation failed",
      errors: %{image: ["must not be empty"]}
    })
  end

  def call(conn, {:error, :storage_failed}) do
    conn
    |> put_status(:bad_gateway)
    |> json(%{
      status: "error",
      message: "Image storage is unavailable",
      errors: ["Please try again later."]
    })
  end

  def call(conn, {:error, :invalid_slot}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      message: "Validation failed",
      errors: %{slot: ["must be between 0 and 9"]}
    })
  end

  def call(conn, {:error, :invalid_images}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      message: "Validation failed",
      errors: %{images: ["must only contain your existing photos"]}
    })
  end

  def call(conn, {:error, :multiple_files_not_supported}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      message: "Validation failed",
      errors: %{image: ["must be uploaded one file per slot"]}
    })
  end

  def call(conn, {:error, :photo_limit_reached}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      message: "Photo limit reached",
      errors: %{images: ["allows at most 10 photos"]}
    })
  end

  def call(conn, {:error, :not_comment_owner}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      status: "error",
      message: "You can only modify your own comments",
      errors: ["You are not the author of this comment."]
    })
  end

  def call(conn, {:error, :forbidden_event_owner}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      status: "error",
      code: "forbidden",
      message: "Only the event creator can modify this event",
      errors: ["You are not the creator of this event."]
    })
  end

  def call(conn, {:error, :blocked}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      status: "error",
      message: "This action is not available",
      errors: ["You cannot interact with this user."]
    })
  end

  def call(conn, {:error, reason})
      when reason in [:self_relationship, :invalid_kind, :invalid_relationship] do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      status: "error",
      message: "Validation failed",
      errors: %{relationship: [relationship_error(reason)]}
    })
  end

  # 4. GENERIC SERVER RETRIES / EXCEPTIONS (500)
  def call(conn, {:error, reason}) do
    # Fallback to standard message string if reason is an internal map/atom
    error_message =
      if is_binary(reason), do: reason, else: "An unexpected internal server error occurred."

    conn
    |> put_status(:internal_server_error)
    |> json(%{
      status: "error",
      message: "Internal server exception",
      errors: [error_message]
    })
  end

  # 5. SECURE CHANGESET INTERPOLATION HELPER
  defp relationship_error(:self_relationship), do: "cannot target yourself"
  defp relationship_error(:invalid_kind), do: "must be one of like, block, or mute"
  defp relationship_error(:invalid_relationship), do: "is invalid"
  defp relationship_error(_reason), do: "is invalid"

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        try do
          # Securely transform key token, falling back to original string on missing atoms
          key_atom = String.to_existing_atom(key)
          opts |> Keyword.get(key_atom, key) |> to_string()
        rescue
          _ -> key
        end
      end)
    end)
  end
end
