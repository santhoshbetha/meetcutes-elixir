defmodule Meetcutes.Accounts.UserTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Meetcutes.GeoPrivacy
  alias Meetcutes.Accounts.User

  describe "registration_changeset/3" do
    test "derives birth_year from age during registration" do
      current_year = Date.utc_today().year

      changeset =
        User.registration_changeset(
          %User{},
          %{
            email: "user@example.com",
            first_name: "John",
            last_name: "Doe",
            phone_number: "+15555550123",
            age: 29
          },
          validate_unique: false,
          validate_phone_number: false,
          hash_password: false
        )

      assert changeset.valid?
      assert Changeset.get_change(changeset, :age) == 29
      assert Changeset.get_change(changeset, :birth_year) == current_year - 29
    end

    test "casts ethnicity when provided" do
      changeset =
        User.registration_changeset(
          %User{},
          %{
            email: "user@example.com",
            first_name: "John",
            last_name: "Doe",
            phone_number: "+15555550123",
            ethnicity: "White / Caucasian"
          },
          validate_unique: false,
          validate_phone_number: false,
          hash_password: false
        )

      assert changeset.valid?
      assert Changeset.get_change(changeset, :ethnicity) == "White / Caucasian"
    end

    test "marks registration-city coordinates as a system default" do
      changeset =
        User.registration_changeset(
          %User{},
          %{
            "email" => "user@example.com",
            "first_name" => "John",
            "last_name" => "Doe",
            "phone_number" => "+15555550123",
            "raw_lat" => 30.2672,
            "raw_lon" => -97.7431
          },
          validate_unique: false,
          validate_phone_number: false,
          hash_password: false
        )

      assert changeset.valid?
      assert is_binary(Changeset.get_change(changeset, :geohash))
      assert Changeset.get_change(changeset, :default_coords_set) == true
      assert Changeset.get_change(changeset, :user_coords_set) == false
      assert Changeset.get_change(changeset, :exact_coords_set) == false
    end
  end

  describe "update_changeset/2" do
    test "computes a fuzzed geohash from raw coordinates" do
      user = %User{}

      :rand.seed(:exsss, {101, 102, 103})
      {fuzzed_lat, fuzzed_lon} = GeoPrivacy.fuzz_coordinates(42.3601, -74.0060)
      expected_geohash = Geohash.encode(fuzzed_lat, fuzzed_lon, 9)

      :rand.seed(:exsss, {101, 102, 103})

      changeset = User.update_changeset(user, %{"raw_lat" => 42.3601, "raw_lon" => -74.0060})

      assert changeset.valid?
      assert Changeset.get_change(changeset, :geohash) == expected_geohash
    end
  end
end
