defmodule Meetcutes.Schema do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, :string, autogenerate: {Ecto.ULID, :generate, []}}
      @foreign_key_type :string
    end
  end
end
