defmodule Meetcutes.ExAws.FinchClient do
  @moduledoc "Finch-based adapter for ExAws"
  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body \\ "", headers \\ [], http_opts \\ []) do
    # Build the Finch request
    # Note: ExAws sometimes sends the body as a tuple for multipart,
    # but Finch handles binary strings best.
    Finch.build(method, url, headers, body)
    # 2. Execute using the named Finch supervisor
    |> Finch.request(Meetcutes.Finch, http_opts)
    |> case do
      {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
        {:ok, %{status_code: status, headers: headers, body: body}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
end
