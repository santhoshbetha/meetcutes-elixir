defmodule Meetcutes.Config.Getting do
  @callback get(any()) :: any()
  @callback get(any(), any()) :: any()

  def get(key), do: get(key, nil)
  def get(key, default), do: impl().get(key, default)

  def impl do
    Application.get_env(:meetcutes, :config_impl, Meetcutes.Config)
  end
end
