defmodule Meetcutes.EventsTest do
  use Meetcutes.DataCase

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Events
  alias Meetcutes.Events.{Event, Location}
  alias Meetcutes.Repo

  describe "search_events/1" do
    test "filters published events using a user geohash as the search origin" do
      {:ok, nearby_location} =
        %Location{}
        |> Location.changeset(%{
          name: "Boston Common",
          latitude: 42.3601,
          longitude: -71.0589
        })
        |> Repo.insert()

      {:ok, far_location} =
        %Location{}
        |> Location.changeset(%{
          name: "Santa Monica Pier",
          latitude: 34.0094,
          longitude: -118.4973
        })
        |> Repo.insert()

      start_at = DateTime.utc_now() |> DateTime.add(2, :day)
      end_at = DateTime.add(start_at, 2, :hour)

      {:ok, nearby_event} =
        %Event{}
        |> Event.changeset(%{
          title: "Nearby Event",
          location_id: nearby_location.id,
          start_at: start_at,
          end_at: end_at,
          status: "PUBLISHED"
        })
        |> Repo.insert()

      {:ok, _far_event} =
        %Event{}
        |> Event.changeset(%{
          title: "Far Event",
          location_id: far_location.id,
          start_at: start_at,
          end_at: end_at,
          status: "PUBLISHED"
        })
        |> Repo.insert()

      events =
        Events.search_events(
          geohash: Geohash.encode(42.3601, -71.0589, 9),
          distance_miles: 15
        )

      assert Enum.any?(events, &(&1.id == nearby_event.id))
      assert Enum.all?(events, &(&1.location.id == nearby_location.id))
    end
  end

  describe "gender_counts/1" do
    test "aggregates attendee gender counts in one SQL query" do
      {:ok, location} =
        %Location{}
        |> Location.changeset(%{
          name: "Count Venue",
          latitude: 30.2672,
          longitude: -97.7431
        })
        |> Repo.insert()

      start_at = DateTime.utc_now() |> DateTime.add(2, :day)
      end_at = DateTime.add(start_at, 2, :hour)

      {:ok, event} =
        %Event{}
        |> Event.changeset(%{
          title: "Count Event",
          location_id: location.id,
          start_at: start_at,
          end_at: end_at,
          status: "PUBLISHED"
        })
        |> Repo.insert()

      male = user_fixture() |> set_gender("Male")
      female = user_fixture() |> set_gender("Female")

      {:ok, _} = Events.join_event(event.id, male)
      {:ok, _} = Events.join_event(event.id, female)

      counts = Events.gender_counts([event.id])

      assert counts[event.id] == %{male_count: 1, female_count: 1}
    end
  end

  describe "age restrictions" do
    setup do
      {:ok, location} =
        %Location{}
        |> Location.changeset(%{
          name: "Age Rule Venue #{System.unique_integer([:positive])}",
          latitude: 30.2672,
          longitude: -97.7431
        })
        |> Repo.insert()

      start_at = DateTime.utc_now() |> DateTime.add(2, :day)
      end_at = DateTime.add(start_at, 2, :hour)

      {:ok, event} =
        Events.create_event(
          %{
            "title" => "Age Rule Event",
            "location_id" => location.id,
            "start_at" => start_at,
            "end_at" => end_at,
            "status" => "PUBLISHED",
            "has_age_restriction" => true,
            "men_min_age" => 21,
            "men_max_age" => 35,
            "women_min_age" => 21,
            "women_max_age" => 35
          },
          user_fixture().id
        )

      %{event: event}
    end

    test "join_event/2 rejects users outside their gender's age range", %{event: event} do
      too_young = user_fixture(%{gender: "Male", age: 20})

      assert {:error, :age_restricted} = Events.join_event(event.id, too_young)
      refute Map.has_key?(Events.get_event(event.id).attendees || %{}, too_young.id)
    end

    test "join_event/2 accepts users inside their gender's age range", %{event: event} do
      eligible = user_fixture(%{gender: "Female", age: 30})

      assert {:ok, joined} = Events.join_event(event.id, eligible)
      assert Map.has_key?(joined.attendees, eligible.id)
    end

    test "the event changeset rejects inverted age bounds" do
      {:ok, location} =
        %Location{}
        |> Location.changeset(%{
          name: "Inverted Rule Venue #{System.unique_integer([:positive])}",
          latitude: 30.2672,
          longitude: -97.7431
        })
        |> Repo.insert()

      start_at = DateTime.utc_now() |> DateTime.add(2, :day)

      changeset =
        %Event{}
        |> Event.changeset(%{
          title: "Invalid Age Rule",
          location_id: location.id,
          start_at: start_at,
          end_at: DateTime.add(start_at, 2, :hour),
          status: "PUBLISHED",
          has_age_restriction: true,
          men_min_age: 40,
          men_max_age: 30,
          women_min_age: 21,
          women_max_age: 35
        })

      refute changeset.valid?

      assert %{men_max_age: ["must be greater than or equal to the minimum age"]} =
               errors_on(changeset)
    end
  end

  defp set_gender(user, gender) do
    {:ok, user} = Accounts.update_user(user, %{gender: gender})
    user
  end
end
