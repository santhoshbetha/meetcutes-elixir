defmodule Meetcutes.Uploads.WaffleStorage do
  @moduledoc """
  Waffle-backed storage adapter for avatar and banner uploads.

  Files are streamed through the existing `Meetcutes.ImageUploader` definition
  so the S3/Cloudflare R2 configuration stays in one place.
  """

  @behaviour Meetcutes.Uploads.Storage

  alias Meetcutes.ImageUploader

  @extensions %{
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/gif" => ".gif",
    "image/webp" => ".webp"
  }

  @impl true
  def store(user, kind, %Plug.Upload{} = upload, content_type) do
    extension = Map.get(@extensions, content_type, ".jpg")
    unique = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    filename = "#{kind}_#{unique}#{extension}"

    case ImageUploader.store_from_path(upload.path, filename, user) do
      {:ok, stored_filename} ->
        {:ok,
         %{
           filename: stored_filename,
           url: ImageUploader.url({stored_filename, user}),
           content_type: content_type
         }}

      {:error, _reason} ->
        {:error, :storage_failed}
    end
  end

  @impl true
  def delete(user, filename) when is_binary(filename) do
    ImageUploader.delete_user_image(user, filename)
  end

  @impl true
  def url(user, filename) when is_binary(filename) do
    ImageUploader.url({filename, user})
  rescue
    _ -> filename
  end
end
