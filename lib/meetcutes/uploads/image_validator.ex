defmodule Meetcutes.Uploads.ImageValidator do
  @moduledoc """
  Validates uploaded images by inspecting their raw bytes.

  Client-supplied content types and file extensions are never trusted. A file
  is only accepted when its leading bytes match a supported image signature and
  its size is within the configured limit.
  """

  @default_max_bytes 5_000_000
  @read_bytes 12
  @hash_chunk_bytes 1_048_576

  @type result :: {:ok, String.t()} | {:error, :invalid_image | :image_too_large | :empty_file}

  @doc """
  Returns the detected MIME type when the upload is a supported image.
  """
  @spec validate(Plug.Upload.t()) :: result()
  def validate(%Plug.Upload{} = upload) do
    with :ok <- validate_size(upload),
         {:ok, content_type} <- detect(upload) do
      {:ok, content_type}
    end
  end

  def validate(_upload), do: {:error, :invalid_image}

  @doc """
  Detects an image MIME type from the first bytes of a file.
  """
  @spec detect(Plug.Upload.t()) :: {:ok, String.t()} | {:error, :invalid_image | :empty_file}
  def detect(%Plug.Upload{path: path}) when is_binary(path) do
    case File.open(path, [:read, :binary], fn file -> IO.binread(file, @read_bytes) end) do
      {:ok, :eof} -> {:error, :empty_file}
      {:ok, data} when is_binary(data) -> detect_bytes(data)
      {:error, _reason} -> {:error, :invalid_image}
    end
  end

  def detect(_upload), do: {:error, :invalid_image}

  @doc """
  Computes a lowercase SHA-256 digest using a bounded 1 MB read loop.

  The file is never loaded into a single BEAM binary, so concurrent mobile
  uploads keep memory usage flat regardless of file size.
  """
  @spec sha256(Plug.Upload.t()) :: {:ok, String.t()} | {:error, :invalid_image}
  def sha256(%Plug.Upload{path: path}) when is_binary(path) do
    case File.open(path, [:read, :binary], fn file ->
           hash_stream(file, :crypto.hash_init(:sha256))
         end) do
      {:ok, {:ok, digest}} -> {:ok, digest}
      _ -> {:error, :invalid_image}
    end
  end

  def sha256(_upload), do: {:error, :invalid_image}

  defp hash_stream(file, context) do
    case IO.binread(file, @hash_chunk_bytes) do
      :eof ->
        {:ok, :crypto.hash_final(context) |> Base.encode16(case: :lower)}

      data when is_binary(data) ->
        hash_stream(file, :crypto.hash_update(context, data))

      {:error, _reason} ->
        {:error, :invalid_image}
    end
  end

  defp detect_bytes(<<0xFF, 0xD8, 0xFF, _::binary>>), do: {:ok, "image/jpeg"}

  defp detect_bytes(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>),
    do: {:ok, "image/png"}

  defp detect_bytes(<<"GIF87a", _::binary>>), do: {:ok, "image/gif"}
  defp detect_bytes(<<"GIF89a", _::binary>>), do: {:ok, "image/gif"}
  defp detect_bytes(<<"RIFF", _size::binary-size(4), "WEBP", _::binary>>), do: {:ok, "image/webp"}
  defp detect_bytes(_bytes), do: {:error, :invalid_image}

  defp validate_size(%Plug.Upload{path: path}) do
    limit = max_bytes()

    case File.stat(path) do
      {:ok, %{size: 0}} -> {:error, :empty_file}
      {:ok, %{size: size}} when size > limit -> {:error, :image_too_large}
      {:ok, _stat} -> :ok
      {:error, _reason} -> {:error, :invalid_image}
    end
  end

  @doc """
  Maximum accepted upload size in bytes.
  """
  def max_bytes do
    :meetcutes
    |> Application.get_env(:max_upload_bytes, @default_max_bytes)
    |> normalize_max_bytes()
  end

  defp normalize_max_bytes(value) when is_integer(value) and value > 0, do: value
  defp normalize_max_bytes(_value), do: @default_max_bytes
end
