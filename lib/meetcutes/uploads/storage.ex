defmodule Meetcutes.Uploads.Storage do
  @moduledoc """
  Behaviour implemented by upload storage adapters.
  """

  @callback store(struct(), atom(), Plug.Upload.t(), String.t()) ::
              {:ok, map()} | {:error, atom()}

  @callback delete(struct(), String.t()) :: :ok | {:error, atom()}

  @callback url(struct(), String.t()) :: String.t()
end
