defmodule Meetcutes.GeoPrivacy do
  @moduledoc """
  Handles coordinate obfuscation using Gaussian noise.
  """

  # Approximately 0.001 degrees is ~111 meters at the equator
  @standard_deviation_degrees 0.0015

  @doc """
  Takes true coordinates and returns fuzzed coordinates shifted in a random direction.
  """
  def fuzz_coordinates(lat, lon) when is_number(lat) and is_number(lon) do
    {noise_lat, noise_lon} = generate_gaussian_noise()

    fuzzed_lat = lat + noise_lat * @standard_deviation_degrees
    fuzzed_lon = lon + noise_lon * @standard_deviation_degrees

    {fuzzed_lat, fuzzed_lon}
  end

  # Box-Muller transform to generate standard normal distributed random variables
  defp generate_gaussian_noise do
    u1 = :rand.uniform()
    u2 = :rand.uniform()

    u1 = if u1 == 0, do: 0.00001, else: u1

    r = :math.sqrt(-2.0 * :math.log(u1))
    theta = 2.0 * :math.pi() * u2

    z0 = r * :math.cos(theta)
    z1 = r * :math.sin(theta)

    {z0, z1}
  end
end
