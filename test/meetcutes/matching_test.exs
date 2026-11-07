defmodule Meetcutes.MatchingTest do
  use Meetcutes.DataCase, async: false

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Matching
  alias Meetcutes.Repo

  @austin {30.2672, -97.7431}

  describe "count_opposite_gender_within_radius/2" do
    test "counts nearby opposite-gender profiles and excludes the viewer, same gender, and far profiles" do
      viewer = nearby_user("Male", @austin)
      _near_female = nearby_user("Female", {30.27, -97.74})
      _near_female_2 = nearby_user("Female", {30.3, -97.7})
      _far_female = nearby_user("Female", {40.7128, -74.006})
      _near_male = nearby_user("Male", {30.27, -97.74})

      assert {:ok, updated} = Matching.refresh_around_user_count(viewer.id)

      assert updated.around_user_count == 2
      assert %DateTime{} = updated.around_user_count_updated_at
    end

    test "returns zero when the viewer has no usable geohash" do
      viewer = user_fixture(%{gender: "Male"})

      assert {:ok, 0} = Matching.count_opposite_gender_within_radius(viewer)
    end
  end

  describe "refresh_if_stale/1" do
    test "refreshes a never-computed count" do
      viewer = nearby_user("Male", @austin)
      _near_female = nearby_user("Female", {30.27, -97.74})

      assert Matching.stale?(viewer)
      refreshed = Matching.refresh_if_stale(viewer)

      assert refreshed.around_user_count == 1
      refute Matching.stale?(refreshed)
    end

    test "leaves a fresh count untouched" do
      viewer = nearby_user("Male", @austin)
      _near_female = nearby_user("Female", {30.27, -97.74})

      fresh = Matching.refresh_if_stale(viewer)

      assert Matching.refresh_if_stale(fresh).around_user_count == fresh.around_user_count

      assert Matching.refresh_if_stale(fresh).around_user_count_updated_at ==
               fresh.around_user_count_updated_at
    end
  end

  defp nearby_user(gender, {latitude, longitude}) do
    user = user_fixture(%{gender: gender})

    Repo.update!(
      Ecto.Changeset.change(user, %{
        geohash: Geohash.encode(latitude, longitude, 9),
        is_active: true,
        is_approved: true
      })
    )
  end
end
