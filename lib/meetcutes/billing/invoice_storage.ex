defmodule Meetcutes.Billing.InvoiceStorage do
  @moduledoc """
  Stores generated invoice PDFs in the stateless Cloudflare R2 bucket.

  The adapter is configurable so tests never touch S3.
  """

  @callback store(struct(), String.t(), binary(), String.t()) ::
              {:ok, %{key: String.t(), url: String.t()}} | {:error, term()}

  @default_adapter Meetcutes.Billing.InvoiceStorage.S3

  def store(user, filename, binary, content_type) do
    adapter().store(user, filename, binary, content_type)
  end

  def adapter do
    Application.get_env(:meetcutes, :invoice_storage, @default_adapter)
  end
end
