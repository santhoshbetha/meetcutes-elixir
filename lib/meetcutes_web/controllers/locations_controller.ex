defmodule MeetcutesWeb.LocationsController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Locations

  @default_distance 241_401
  @max_distance 1_000_000

  @doc """
  GET /api/v1/locations/autocomplete

  Returns nearby event locations so the event form can detect an address that
  is already in use. `distance` is expressed in metres, matching the legacy
  client call.
  """
  def autocomplete(conn, params) do
    with {:ok, lat} <- parse_coordinate(params, "lat", -90, 90),
         {:ok, lng} <- parse_coordinate(params, "lng", -180, 180),
         {:ok, distance} <- parse_distance(params) do
      locations = Locations.autocomplete(lat, lng, distance)

      conn
      |> put_status(:ok)
      |> json(%{
        status: "success",
        data: %{locations: Enum.map(locations, &serialize/1)}
      })
    else
      {:error, field} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          message: "Validation failed",
          errors: %{field => ["is invalid"]}
        })
    end
  end

  defp serialize(location) do
    %{
      id: location.id,
      name: location.name,
      street: location.street,
      city: location.locality,
      state: location.state,
      postal_code: location.postal_code,
      latitude: location.latitude,
      longitude: location.longitude
    }
  end

  defp parse_coordinate(params, key, min, max) do
    case parse_number(Map.get(params, key)) do
      value when is_number(value) and value >= min and value <= max -> {:ok, value}
      _ -> {:error, key}
    end
  end

  defp parse_distance(params) do
    case Map.get(params, "distance") do
      nil ->
        {:ok, @default_distance}

      _value ->
        case parse_number(Map.get(params, "distance")) do
          value when is_number(value) and value > 0 and value <= @max_distance ->
            {:ok, value}

          _ ->
            {:error, "distance"}
        end
    end
  end

  defp parse_number(nil), do: nil

  defp parse_number(value) when is_number(value), do: value

  defp parse_number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp parse_number(_value), do: nil
end
