defmodule Meetcutes.ImageUploader do
  @moduledoc """
  Image uploader using Waffle with ExAws S3/Cloudflare R2 support.

  This module handles file uploads to S3-compatible storage (including Cloudflare R2).
  It supports image files (.jpg, .jpeg, .gif, .png, .webp) and organizes them
  by user in the storage bucket.

  ## Configuration

  Set the following environment variables:

  - `AWS_ACCESS_KEY_ID`: Your AWS/Cloudflare R2 access key
  - `AWS_SECRET_ACCESS_KEY`: Your AWS/Cloudflare R2 secret key
  - `AWS_S3_BUCKET`: The bucket name
  - `AWS_REGION`: Region (use 'auto' for Cloudflare R2)
  - `AWS_S3_HOST`: The endpoint host (e.g., your-account-id.r2.cloudflarestorage.com)
  - `AWS_S3_ASSET_HOST`: CDN/custom domain for serving assets

  ## Usage

      # Upload a file
      {:ok, filename} = ImageUploader.store({file_struct, user})

      # Get the public URL
      url = ImageUploader.url({filename, user})

      # Delete a file
      ImageUploader.delete({filename, user})
  """

  use Waffle.Definition

  @versions [:original]
  @extension_whitelist ~w(.jpg .jpeg .gif .png .webp)

  # Validate file extensions #called by waffle (ImageUploader.validate({uploaded_file, user}))
  def validate({file, _}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()
    Enum.member?(@extension_whitelist, file_extension)
  end

  # Override the bucket name:
  def bucket do
    System.get_env("AWS_S3_BUCKET") || "meetcutes-images"
  end

  # Override the key function (optional):
  def filename(version, {file, _user}) do
    "#{version}_#{Path.basename(file.file_name, Path.extname(file.file_name))}"
  end

  # Override the storage directory:
  def storage_dir(_version, {_file, user}) do
    "uploads/users/#{user.id}/images"
  end

  # Provide a default URL if there hasn't been a file uploaded
  def default_url(version, _user) do
    "/images/default_#{version}.png"
  end

  # Specify custom headers for s3 objects
  # Available options are [:cache_control, :content_disposition,
  #    :content_encoding, :content_length, :content_type,
  #    :expect, :expires, :storage_class, :website_redirect_location,
  #    :server_side_encryption, :server_side_encryption_aws_kms_key_id,
  #    :server_side_encryption_context, :server_side_encryption_customer_algorithm,
  #    :server_side_encryption_customer_key, :server_side_encryption_customer_key_md5,
  #    :ssekms_key_id, :ssekms_encryption_context, :bucket_key_enabled,
  #    :request_payer, :tagging, :object_lock_mode, :object_lock_retain_until_date,
  #    :object_lock_legal_hold_status]
  def s3_object_headers(_version, {file, _user}) do
    [content_type: MIME.from_path(file.file_name)]
  end

  # Additional functions for managing user images
  def list_user_images(user) do
    user_dir = "uploads/users/#{user.id}/images"

    case list_objects_in_directory(user_dir) do
      {:ok, objects} ->
        # Transform S3 objects into image metadata
        Enum.map(objects, fn object ->
          %{
            filename: Path.basename(object.key),
            key: object.key,
            url: url({Path.basename(object.key), user}),
            size: object.size,
            last_modified: object.last_modified,
            uploaded_at: object.last_modified
          }
        end)

      {:error, _reason} ->
        # Return empty list if we can't list objects
        []
    end
  end

  def get_user_avatar(user) do
    case user.avatar do
      %{"filename" => filename} when is_binary(filename) ->
        # Generate the S3 URL for the avatar filename
        avatar_url = url({filename, user})
        {:ok, avatar_url}

      %{"url" => url} when is_binary(url) ->
        # Return the direct URL
        {:ok, url}

      _ ->
        # No avatar set
        {:error, :not_found}
    end
  end

  def delete_user_image(user, filename) do
    # Delete a specific image for a user from S3
    key = "uploads/users/#{user.id}/images/#{filename}"

    case delete_object(key) do
      {:ok, _} -> :ok
      {:error, _reason} -> {:error, :delete_failed}
    end
  end

  def delete_all_user_images(user) do
    # Delete all images for a user from S3
    # List all objects in the user's directory and delete them
    user_dir = "uploads/users/#{user.id}/images"

    case list_objects_in_directory(user_dir) do
      {:ok, objects} ->
        # Delete all objects in the directory
        Enum.each(objects, fn object ->
          delete_object(object.key)
        end)

        :ok

      {:error, _reason} ->
        # If we can't list objects, that's okay - the user is being deleted anyway
        :ok
    end
  end

  @doc """
  Helper to store a file given a local path and filename. This builds a Waffle.File
  struct and delegates to the generated `store/1` function.
  """
  @spec store_from_path(String.t(), String.t(), any()) :: {:ok, String.t()} | {:error, any()}
  def store_from_path(path, filename, user) when is_binary(path) and is_binary(filename) do
    # Waffle's store/1 accepts a map for the file details.
    # It will convert this into a Waffle.File struct for you.
    file_payload = %{path: path, filename: filename}

    case store({file_payload, user}) do
      {:ok, stored_filename} ->
        {:ok, stored_filename}

      {:error, reason} ->
        # Log the actual reason for better debugging in Cloudflare R2
        IO.warn("Waffle store failed: #{inspect(reason)}")
        {:error, :store_failed}
    end
  end

  # Helper function to list objects in a directory
  defp list_objects_in_directory(prefix) do
    bucket = bucket()

    # Use ExAws to list objects with the given prefix
    ExAws.S3.list_objects_v2(bucket, prefix: prefix)
    |> ExAws.request()
    |> case do
      {:ok, %{body: %{contents: objects}}} -> {:ok, objects}
      {:error, reason} -> {:error, reason}
    end
  end

  # Helper function to delete an object from S3
  defp delete_object(key) do
    bucket = bucket()

    ExAws.S3.delete_object(bucket, key)
    |> ExAws.request()
  end
end
