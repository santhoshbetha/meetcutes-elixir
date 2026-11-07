defmodule MeetcutesWeb.UploadJSON do
  @moduledoc """
  JSON views for upload responses.
  """

  def image(%{media: media}) do
    %{
      data: %{
        url: media.url,
        filename: media.filename,
        content_type: media.content_type
      }
    }
  end

  def images(%{images: images}) do
    %{
      data: images
    }
  end

  def avatar(%{avatar_url: avatar_url} = payload) do
    data =
      case Map.get(payload, :media) do
        nil ->
          %{avatar_url: avatar_url}

        media ->
          %{
            avatar_url: avatar_url,
            filename: media.filename,
            content_type: media.content_type
          }
      end

    %{data: data}
  end

  def error(%{changeset: changeset}) do
    %{
      errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
    }
  end

  def error(%{error: error}) do
    %{
      errors: %{
        detail: error
      }
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
