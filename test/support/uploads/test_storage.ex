defmodule Meetcutes.Uploads.TestStorage do
  @moduledoc """
  In-memory storage adapter used by the test suite.

  No network or filesystem writes happen here; the returned metadata is enough
  for the API and serializer tests to assert on.
  """

  @behaviour Meetcutes.Uploads.Storage

  @impl true
  def store(user, kind, %Plug.Upload{} = upload, content_type) do
    unique = System.unique_integer([:positive])
    extension = Path.extname(upload.filename || "")
    filename = "#{kind}_#{unique}#{extension}"

    {:ok,
     %{
       filename: filename,
       url: url(user, filename),
       content_type: content_type
     }}
  end

  @impl true
  def delete(_user, _filename), do: :ok

  @impl true
  def url(user, filename) when is_binary(filename) do
    "https://cdn.test/#{user.id}/#{filename}"
  end
end
