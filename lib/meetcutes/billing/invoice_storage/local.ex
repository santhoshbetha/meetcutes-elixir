defmodule Meetcutes.Billing.InvoiceStorage.Local do
  @moduledoc """
  No-op invoice storage for local development and E2E runs.

  It returns the same key/url shape as the S3 adapter without writing a file.
  Enable it with `INVOICE_STORAGE=local`.
  """

  @behaviour Meetcutes.Billing.InvoiceStorage

  @impl true
  def store(user, filename, _binary, _content_type) do
    key = "invoices/users/#{user.id}/#{filename}"

    {:ok, %{key: key, url: "http://localhost/invoices/#{key}"}}
  end
end
