defmodule MeetcutesWeb.DiscussionControllerTest do
  use MeetcutesWeb.ConnCase, async: false

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Events
  alias Meetcutes.Locations

  @austin_lat 30.2672
  @austin_lng -97.7431

  setup %{conn: conn} do
    author =
      user_fixture()
      |> with_identity("comment_author")

    other =
      user_fixture()
      |> with_identity("comment_other")

    event = event_fixture(author)

    %{
      conn: put_bearer(conn, author),
      author: author,
      other: other,
      event: event
    }
  end

  describe "GET /api/events/:event_id/comments" do
    test "lists comments for the event", %{conn: conn, author: author, event: event} do
      {:ok, first} =
        Meetcutes.Discussion.create_comment(author, event.id, %{"content" => "First"})

      {:ok, second} =
        Meetcutes.Discussion.create_comment(author, event.id, %{"content" => "Second"})

      conn = get(conn, ~p"/api/events/#{event.id}/comments")

      assert %{"data" => comments} = json_response(conn, 200)
      assert Enum.map(comments, & &1["id"]) |> Enum.sort() == Enum.sort([first.id, second.id])
      assert Enum.all?(comments, &(&1["event_id"] == event.id))
      assert Enum.all?(comments, &(&1["user_id"] == author.id))
      assert Enum.all?(comments, &(&1["user"]["handle"] == author.nickname))
    end

    test "returns 404 when the event does not exist", %{conn: conn} do
      conn = get(conn, ~p"/api/events/does-not-exist/comments")
      assert %{"status" => "error"} = json_response(conn, 404)
    end
  end

  describe "POST /api/events/:event_id/comments" do
    test "creates a comment owned by the bearer user", %{
      conn: conn,
      author: author,
      other: other,
      event: event
    } do
      other_event = event_fixture(other)

      conn =
        post(conn, ~p"/api/events/#{event.id}/comments", %{
          "comment" => %{
            "content" => "Hello discussion",
            # These must be ignored: identity and event come from the token/URL.
            "user_id" => other.id,
            "event_id" => other_event.id
          }
        })

      assert %{"data" => comment} = json_response(conn, 201)
      assert comment["content"] == "Hello discussion"
      assert comment["user_id"] == author.id
      assert comment["event_id"] == event.id
      assert comment["user"]["id"] == author.id
    end

    test "requires content", %{conn: conn, event: event} do
      conn =
        post(conn, ~p"/api/events/#{event.id}/comments", %{"comment" => %{"content" => ""}})

      assert %{"status" => "error", "errors" => %{"content" => _}} =
               json_response(conn, 422)
    end

    test "returns 404 when the event does not exist", %{conn: conn} do
      conn =
        post(conn, ~p"/api/events/does-not-exist/comments", %{
          "comment" => %{"content" => "Orphan"}
        })

      assert %{"status" => "error"} = json_response(conn, 404)
    end

    test "rejects unauthenticated requests", %{event: event} do
      conn =
        build_conn()
        |> post(~p"/api/events/#{event.id}/comments", %{"comment" => %{"content" => "Nope"}})

      assert %{"status" => "error"} = json_response(conn, 401)
    end
  end

  describe "PUT /api/comments/:id" do
    test "updates the author's own comment and ignores ownership fields", %{
      conn: conn,
      author: author,
      other: other,
      event: event
    } do
      {:ok, comment} =
        Meetcutes.Discussion.create_comment(author, event.id, %{"content" => "Before"})

      conn =
        put(conn, ~p"/api/comments/#{comment.id}", %{
          "comment" => %{
            "content" => "After",
            "user_id" => other.id,
            "event_id" => "some-other-event"
          }
        })

      assert %{"data" => updated} = json_response(conn, 200)
      assert updated["content"] == "After"
      assert updated["user_id"] == author.id
      assert updated["event_id"] == event.id
    end

    test "returns 403 when the bearer user is not the author", %{
      conn: conn,
      author: author,
      other: other,
      event: event
    } do
      {:ok, comment} =
        Meetcutes.Discussion.create_comment(author, event.id, %{"content" => "Mine"})

      conn = put_bearer(conn, other)

      conn =
        put(conn, ~p"/api/comments/#{comment.id}", %{"comment" => %{"content" => "Hijacked"}})

      assert %{"status" => "error"} = json_response(conn, 403)
      assert Meetcutes.Discussion.get_comment(comment.id).content == "Mine"
    end

    test "returns 404 for a missing comment", %{conn: conn} do
      conn = put(conn, ~p"/api/comments/does-not-exist", %{"comment" => %{"content" => "X"}})
      assert %{"status" => "error"} = json_response(conn, 404)
    end
  end

  describe "DELETE /api/comments/:id" do
    test "deletes the author's own comment", %{conn: conn, author: author, event: event} do
      {:ok, comment} =
        Meetcutes.Discussion.create_comment(author, event.id, %{"content" => "Delete me"})

      conn = delete(conn, ~p"/api/comments/#{comment.id}")

      assert response(conn, 204) == ""
      assert Meetcutes.Discussion.get_comment(comment.id) == nil
    end

    test "returns 403 when the bearer user is not the author", %{
      conn: conn,
      author: author,
      other: other,
      event: event
    } do
      {:ok, comment} =
        Meetcutes.Discussion.create_comment(author, event.id, %{"content" => "Keep me"})

      conn = conn |> put_bearer(other) |> delete(~p"/api/comments/#{comment.id}")

      assert %{"status" => "error"} = json_response(conn, 403)
      assert Meetcutes.Discussion.get_comment(comment.id)
    end

    test "returns 404 for a missing comment", %{conn: conn} do
      conn = delete(conn, ~p"/api/comments/does-not-exist")
      assert %{"status" => "error"} = json_response(conn, 404)
    end
  end

  defp put_bearer(conn, user) do
    token = Accounts.generate_user_session_token(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp event_fixture(creator) do
    location = location_fixture()
    start_at = DateTime.add(DateTime.utc_now(:second), 7, :day)

    {:ok, event} =
      Events.create_event(
        %{
          "title" => "Discussion Event #{System.unique_integer([:positive])}",
          "content" => "Talk about it",
          "location_id" => location.id,
          "start_at" => start_at,
          "end_at" => DateTime.add(start_at, 2, :hour),
          "status" => "PUBLISHED"
        },
        creator.id
      )

    event
  end

  defp location_fixture do
    {:ok, location} =
      Locations.create_location(%{
        name: "Venue #{System.unique_integer([:positive])}",
        street: "1 Congress Ave",
        locality: "Austin",
        state: "TX",
        postal_code: "78701",
        latitude: @austin_lat,
        longitude: @austin_lng
      })

    location
  end

  defp with_identity(user, nickname) do
    {:ok, user} =
      Accounts.update_user(user, %{nickname: nickname, gender: "Female", first_name: "Test"})

    user
  end
end
