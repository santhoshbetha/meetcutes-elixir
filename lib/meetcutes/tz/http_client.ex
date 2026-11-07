defmodule Meetcutes.Tz.HTTPClient do
  @behaviour Tz.HTTP.HTTPClient
  alias Tz.HTTP.HTTPResponse

  @impl Tz.HTTP.HTTPClient
  def request(hostname, path) do
    url = "https://" <> Path.join(hostname, path)

    # Use your app's Finch supervisor name
    case Finch.build(:get, url) |> Finch.request(Meetcutes.Finch) do
      {:ok, response} ->
        %HTTPResponse{
          status_code: response.status,
          body: response.body
        }

      {:error, reason} ->
        # Tz expects an HTTPResponse struct; you can return a 500 or handle as needed
        # depending on how you want the library to react to network failure.
        IO.warn("Tz failed to fetch data: #{inspect(reason)}")
        %HTTPResponse{status_code: 500, body: ""}
    end
  end
end
