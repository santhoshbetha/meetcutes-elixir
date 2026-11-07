defmodule Meetcutes.Billing.InvoiceStorageStub do
  @moduledoc """
  In-memory invoice storage used by tests.
  """

  @behaviour Meetcutes.Billing.InvoiceStorage

  @impl true
  def store(user, filename, binary, content_type) do
    key = "invoices/users/#{user.id}/#{filename}"

    {:ok,
     %{
       key: key,
       url: "https://cdn.test/#{key}",
       content_type: content_type,
       size: byte_size(binary)
     }}
  end
end
