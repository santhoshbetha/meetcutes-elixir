defmodule Meetcutes.Uploads do
  @moduledoc """
  Entry point for validated avatar and banner uploads.

  The concrete storage backend is configurable so tests never touch S3:

      config :meetcutes, :image_storage, Meetcutes.Uploads.WaffleStorage
  """

  alias Meetcutes.Uploads.ImageValidator

  @kinds [:avatar, :banner, :image]

  @doc """
  Validates and stores an uploaded image for a user.

  Returns the metadata map that is persisted on the user record.
  """
  @spec store(struct(), atom(), Plug.Upload.t()) ::
          {:ok, %{filename: String.t(), url: String.t(), content_type: String.t()}}
          | {:error, atom()}
  def store(user, kind, %Plug.Upload{} = upload) when kind in @kinds do
    with {:ok, content_type} <- ImageValidator.validate(upload) do
      storage().store(user, kind, upload, content_type)
    end
  end

  def store(_user, _kind, _upload), do: {:error, :invalid_image}

  @doc """
  Removes a stored file. Storage failures are best-effort: metadata is already
  gone by the time this runs, so a missing object must not fail the request.
  """
  @spec delete(struct(), String.t()) :: :ok
  def delete(user, filename) when is_binary(filename) and filename != "" do
    _ = storage().delete(user, filename)
    :ok
  end

  def delete(_user, _filename), do: :ok

  @doc """
  Validates an upload without storing it.
  """
  def validate(%Plug.Upload{} = upload) do
    case ImageValidator.validate(upload) do
      {:ok, _content_type} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(nil), do: :ok
  def validate(_upload), do: {:error, :invalid_image}

  @doc """
  Builds the public URL for a stored filename.
  """
  @spec url(struct(), String.t()) :: String.t()
  def url(user, filename) when is_binary(filename) do
    storage().url(user, filename)
  end

  @doc """
  Returns the configured storage adapter.
  """
  def storage do
    Application.get_env(:meetcutes, :image_storage, Meetcutes.Uploads.WaffleStorage)
  end
end
