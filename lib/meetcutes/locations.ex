defmodule Meetcutes.Locations do
  @moduledoc """
  The Locations context.
  """

  import Ecto.Query, warn: false
  alias Meetcutes.Repo

  alias Meetcutes.Events.Location

  @doc """
  Returns the list of locations.
  """
  def list_locations do
    Repo.all(Location)
  end

  @doc """
  Gets a single location.
  """
  def get_location!(id), do: Repo.get!(Location, id)

  @doc """
  Gets a single location without raising.
  """
  def get_location(id), do: Repo.get(Location, id)

  @doc """
  Creates a location.
  """
  def create_location(attrs \\ %{}) do
    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a location.
  """
  def update_location(%Location{} = location, attrs) do
    location
    |> Location.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a location.
  """
  def delete_location(%Location{} = location) do
    Repo.delete(location)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking location changes.
  """
  def change_location(%Location{} = location, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end

  @doc """
  Finds or creates a location based on the provided attributes.
  Uses name as the primary identifier for uniqueness.
  """
  def find_or_create_location(attrs) when is_map(attrs) do
    case Map.get(attrs, "name") || Map.get(attrs, :name) do
      nil ->
        {:error, :missing_name}

      name ->
        # Try to find existing location by name
        case Repo.get_by(Location, name: name) do
          nil ->
            # Create new location
            create_location(attrs)

          existing_location ->
            # Return existing location
            {:ok, existing_location}
        end
    end
  end

  @doc """
  Finds a location by name.
  """
  def get_location_by_name(name) do
    Repo.get_by(Location, name: name)
  end

  @doc """
  Finds a location by its street address components.

  All four values must be present; otherwise the caller should create a new
  location instead. This keeps the event form from duplicating a venue every
  time someone re-enters the same address.
  """
  def find_by_address(street, locality, state, postal_code) do
    if Enum.all?([street, locality, state, postal_code], &(is_binary(&1) and &1 != "")) do
      Repo.get_by(Location,
        street: street,
        locality: locality,
        state: state,
        postal_code: postal_code
      )
    end
  end

  @default_radius_metres 241_401
  @max_radius_metres 1_000_000

  @doc """
  Returns distinct event locations within `distance_metres` of a point,
  nearest first.

  The React event form uses this to spot an address that already exists, so
  only the fields needed for that comparison are meaningful.
  """
  def autocomplete(lat, lng, distance_metres \\ @default_radius_metres)
      when is_number(lat) and is_number(lng) and is_number(distance_metres) do
    radius_metres = distance_metres |> max(0) |> min(@max_radius_metres)
    radius_miles = radius_metres / 1609.344

    Location
    |> where([l], not is_nil(l.latitude) and not is_nil(l.longitude))
    |> within_bounding_box(lat, lng, radius_miles)
    |> Repo.all()
    |> Enum.map(fn location ->
      {distance_miles(lat, lng, location.latitude, location.longitude), location}
    end)
    |> Enum.filter(fn {distance, _location} -> distance <= radius_miles end)
    |> Enum.sort_by(fn {distance, location} -> {distance, location.name} end)
    |> Enum.uniq_by(fn {_distance, location} ->
      {location.street, location.locality, location.state, location.postal_code}
    end)
    |> Enum.map(fn {_distance, location} -> location end)
  end

  @doc """
  Great-circle distance between two coordinates, in miles.
  """
  def distance_miles(lat1, lon1, lat2, lon2) do
    earth_radius = 3958.8

    lat1_rad = deg_to_rad(lat1)
    lon1_rad = deg_to_rad(lon1)
    lat2_rad = deg_to_rad(lat2)
    lon2_rad = deg_to_rad(lon2)

    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(dlon / 2) * :math.sin(dlon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    earth_radius * c
  end

  defp deg_to_rad(degrees), do: degrees * :math.pi() / 180

  defp within_bounding_box(query, lat, lng, radius_miles) do
    lat_delta = radius_miles / 69.0
    lon_scale = max(abs(:math.cos(deg_to_rad(lat))), 0.01)
    lng_delta = radius_miles / (69.0 * lon_scale)

    where(
      query,
      [l],
      l.latitude >= ^(lat - lat_delta) and
        l.latitude <= ^(lat + lat_delta) and
        l.longitude >= ^(lng - lng_delta) and
        l.longitude <= ^(lng + lng_delta)
    )
  end
end
