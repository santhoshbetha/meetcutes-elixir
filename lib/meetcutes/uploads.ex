defmodule Meetcutes.Uploads do
  @moduledoc """
  Entry point for validated avatar and banner uploads.

  The concrete storage backend is configurable so tests never touch S3:

      config :meetcutes, :image_storage, Meetcutes.Uploads.WaffleStorage
  """

  alias Meetcutes.Uploads.ImageValidator
  alias Meetcutes.Workers.DeleteR2ObjectWorker

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
  Validates, hashes, and stores an upload, returning the media metadata plus
  the streaming SHA-256 digest. The storage write happens before any database
  transaction so a slow R2/S3 transfer never pins a pool connection.
  """
  @spec prepare(struct(), atom(), Plug.Upload.t()) ::
          {:ok, map()} | {:error, atom()}
  def prepare(user, kind, %Plug.Upload{} = upload) when kind in @kinds do
    with {:ok, content_type} <- ImageValidator.validate(upload),
         {:ok, digest} <- ImageValidator.sha256(upload),
         {:ok, media} <- storage().store(user, kind, upload, content_type) do
      {:ok, Map.put(media, :sha256, digest)}
    end
  end

  def prepare(_user, _kind, _upload), do: {:error, :invalid_image}

  @doc """
  Enqueues asynchronous deletion of a stored object.
  """
  @spec enqueue_delete(struct(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_delete(%{id: user_id}, filename)
      when is_binary(user_id) and is_binary(filename) and filename != "" do
    %{user_id: user_id, filename: filename}
    |> DeleteR2ObjectWorker.new()
    |> Oban.insert()
  end

  def enqueue_delete(_user, _filename), do: {:ok, nil}

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
