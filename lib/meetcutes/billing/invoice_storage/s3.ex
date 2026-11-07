defmodule Meetcutes.Billing.InvoiceStorage.S3 do
  @moduledoc """
  Streams invoice PDFs into the configured S3-compatible bucket (R2 in prod).
  """

  @behaviour Meetcutes.Billing.InvoiceStorage

  @impl true
  def store(user, filename, binary, content_type) do
    key = "invoices/users/#{user.id}/#{filename}"
    bucket = Meetcutes.ImageUploader.bucket()

    case ExAws.S3.put_object(bucket, key, binary, content_type: content_type)
         |> ExAws.request() do
      {:ok, _response} ->
        {:ok, %{key: key, url: public_url(key)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp public_url(key) do
    case Application.get_env(:waffle, :asset_host) do
      host when is_binary(host) and host != "" ->
        "#{String.trim_trailing(host, "/")}/#{key}"

      _ ->
        key
    end
  rescue
    _ -> key
  end
end
