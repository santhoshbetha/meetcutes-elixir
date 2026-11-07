defmodule MeetcutesWeb.PublicController do
  use MeetcutesWeb, :controller

  @doc """
  GET /api/v1/public/global-announcement

  Unauthenticated, read-only public configuration endpoint.
  """
  def global_announcement(conn, _params) do
    message =
      case Application.get_env(:meetcutes, :global_announcement) do
        value when is_binary(value) ->
          case String.trim(value) do
            "" -> nil
            trimmed -> trimmed
          end

        _ ->
          nil
      end

    json(conn, %{message: message})
  end
end
