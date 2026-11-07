defmodule MeetcutesWeb.ProfilesControllerTest do
  use MeetcutesWeb.ConnCase, async: false

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts
  alias Meetcutes.Accounts.User
  alias Meetcutes.Relationships
  alias Meetcutes.Repo

  setup %{conn: conn} do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)
    conn = put_req_header(conn, "authorization", "Bearer " <> token)

    %{conn: conn, user: user, token: token}
  end

  describe "GET /api/v1/profiles/me" do
    test "returns the canonical profile with scores and visibility preferences", %{
      conn: conn,
      user: user
    } do
      conn = get(conn, ~p"/api/v1/profiles/me")

      assert %{"status" => "success", "data" => %{"profile" => profile}} =
               json_response(conn, 200)

      assert profile["id"] == user.id
      assert profile["email"] == user.email
      assert profile["empathy_score"] == 0
      assert profile["narcissism_flags"] == 0
      assert profile["images"] == []
      assert profile["image_urls"] == []
      assert profile["avatar_url"] == nil
      assert profile["visibility_preference"] == "both"

      assert profile["visibility_preferences"] == %{
               "visibility_preference" => "both",
               "email_search" => nil,
               "phone_number_search" => nil,
               "user_handle_search" => nil,
               "only_hundred_miles_visibility" => nil
             }
    end

    test "requires authentication" do
      conn = build_conn() |> get(~p"/api/v1/profiles/me")

      assert %{"status" => "error"} = json_response(conn, 401)
    end
  end

  describe "PATCH /api/v1/profiles/me" do
    test "accepts canonical and legacy profile keys", %{conn: conn, user: user} do
      phone = unique_user_phone()

      conn =
        patch(conn, ~p"/api/v1/profiles/me", %{
          "firstname" => "Ada",
          "lastname" => "Lovelace",
          "phonenumber" => phone,
          "bio" => "Countess of computing",
          "emailsearch" => "false",
          "hidelastname" => "true",
          "visibilitypreference" => "online-only"
        })

      assert %{"status" => "success", "data" => %{"profile" => profile}} =
               json_response(conn, 200)

      assert profile["first_name"] == "Ada"
      assert profile["last_name"] == "Lovelace"
      assert profile["phone_number"] == phone
      assert profile["bio"] == "Countess of computing"
      assert profile["email_search"] == false
      assert profile["hide_last_name"] == true
      assert profile["visibility_preference"] == "online-only"

      stored = Repo.get!(User, user.id)
      assert stored.first_name == "Ada"
      assert stored.hide_last_name == true
      assert stored.settings["visibility_preference"] == "online-only"
    end

    test "merges settings instead of replacing them", %{conn: conn, user: user} do
      assert {:ok, _} =
               user
               |> User.profile_changeset(%{"settings" => %{"theme" => "dark"}})
               |> Repo.update()

      conn =
        patch(conn, ~p"/api/v1/profiles/me", %{"visibilitypreference" => "events-only"})

      assert %{"data" => %{"profile" => profile}} = json_response(conn, 200)
      assert profile["visibility_preference"] == "events-only"
      assert profile["settings"]["theme"] == "dark"
    end

    test "rejects a nickname that is already taken", %{conn: conn} do
      taken = user_fixture(%{nickname: "taken_handle"})

      conn = patch(conn, ~p"/api/v1/profiles/me", %{"nickname" => taken.nickname})

      assert %{"status" => "error", "message" => "Validation failed", "errors" => errors} =
               json_response(conn, 422)

      assert errors["nickname"]
    end

    test "rejects a phone number that is already taken", %{conn: conn} do
      taken = user_fixture()

      conn = patch(conn, ~p"/api/v1/profiles/me", %{"phonenumber" => taken.phone_number})

      assert %{"status" => "error", "errors" => errors} = json_response(conn, 422)
      assert errors["phone_number"]
    end

    test "stores a validated avatar upload", %{conn: conn, user: user} do
      upload = image_upload(valid_png(), "avatar.png")

      conn = patch(conn, ~p"/api/v1/profiles/me", %{"avatar" => upload})

      assert %{"data" => %{"profile" => profile}} = json_response(conn, 200)
      assert profile["avatar"]["filename"] =~ "avatar_"
      assert profile["avatar"]["content_type"] == "image/png"
      assert profile["avatar_url"] =~ "https://cdn.test/#{user.id}/avatar_"

      stored = Repo.get!(User, user.id)
      assert stored.avatar["filename"] =~ "avatar_"
    end

    test "rejects a file whose bytes are not an image", %{conn: conn, user: user} do
      upload = image_upload("this is definitely not an image", "avatar.png")

      conn = patch(conn, ~p"/api/v1/profiles/me", %{"avatar" => upload})

      assert %{"status" => "error", "message" => "Validation failed", "errors" => errors} =
               json_response(conn, 422)

      assert errors["image"]
      assert Repo.get!(User, user.id).avatar == nil
    end

    test "rejects a multi-file profile payload when either file is invalid", %{
      conn: conn,
      user: user
    } do
      avatar = image_upload(valid_png(), "avatar.png")
      banner = image_upload("not an image", "banner.png")

      conn = patch(conn, ~p"/api/v1/profiles/me", %{"avatar" => avatar, "banner" => banner})

      assert %{"status" => "error", "errors" => errors} = json_response(conn, 422)
      assert errors["image"]

      # Both writes are rejected; the valid avatar must not leak into storage.
      stored = Repo.get!(User, user.id)
      assert stored.avatar == nil
      assert stored.banner == nil
    end

    test "rejects an upload larger than the configured limit", %{conn: conn, user: user} do
      previous = Application.get_env(:meetcutes, :max_upload_bytes)
      Application.put_env(:meetcutes, :max_upload_bytes, 4)
      on_exit(fn -> Application.put_env(:meetcutes, :max_upload_bytes, previous) end)

      upload = image_upload(valid_png(), "avatar.png")
      conn = patch(conn, ~p"/api/v1/profiles/me", %{"avatar" => upload})

      assert %{"status" => "error", "message" => message} = json_response(conn, 413)
      assert message =~ "too large"
      assert Repo.get!(User, user.id).avatar == nil
    end
  end

  describe "POST /api/v1/profiles/me/images" do
    test "stores a photo in the requested slot", %{conn: conn, user: user} do
      upload = image_upload(valid_png(), "photo.png")

      conn =
        post(conn, ~p"/api/v1/profiles/me/images", %{"slot" => "0", "file" => upload})

      assert %{"data" => %{"profile" => profile}} = json_response(conn, 200)
      assert [filename] = profile["images"]
      assert filename =~ "image_"
      assert [url] = profile["image_urls"]
      assert url =~ "https://cdn.test/#{user.id}/image_"

      assert Repo.get!(User, user.id).images == [filename]
    end

    test "pads gaps with empty slots and preserves earlier photos", %{conn: conn} do
      first = image_upload(valid_png(), "first.png")
      conn = post(conn, ~p"/api/v1/profiles/me/images", %{"slot" => "0", "file" => first})
      assert %{"data" => %{"profile" => %{"images" => [first_name]}}} = json_response(conn, 200)

      third = image_upload(valid_png(), "third.png")
      conn = post(conn, ~p"/api/v1/profiles/me/images", %{"slot" => "2", "file" => third})

      assert %{"data" => %{"profile" => profile}} = json_response(conn, 200)
      assert profile["images"] == [first_name, "", profile["images"] |> Enum.at(2)]
      assert Enum.at(profile["image_urls"], 0) =~ "https://cdn.test/"
      assert Enum.at(profile["image_urls"], 1) == nil
      assert Enum.at(profile["image_urls"], 2) =~ "https://cdn.test/"
    end

    test "rejects slots outside 0..9", %{conn: conn} do
      upload = image_upload(valid_png(), "photo.png")

      conn = post(conn, ~p"/api/v1/profiles/me/images", %{"slot" => "10", "file" => upload})

      assert %{"status" => "error", "errors" => errors} = json_response(conn, 422)
      assert errors["slot"]
    end

    test "rejects a file whose bytes are not an image", %{conn: conn, user: user} do
      upload = image_upload("not an image", "photo.png")

      conn =
        post(conn, ~p"/api/v1/profiles/me/images", %{"slot" => "0", "file" => upload})

      assert %{"status" => "error", "errors" => errors} = json_response(conn, 422)
      assert errors["image"]
      assert Repo.get!(User, user.id).images == []
    end

    test "rejects a multi-file payload instead of picking one", %{conn: conn, user: user} do
      first = image_upload(valid_png(), "first.png")
      second = image_upload(valid_png(), "second.png")

      conn =
        post(conn, ~p"/api/v1/profiles/me/images", %{
          "slot" => "0",
          "file" => [first, second]
        })

      assert %{"status" => "error", "errors" => errors} = json_response(conn, 422)
      assert errors["image"] == ["must be uploaded one file per slot"]
      assert Repo.get!(User, user.id).images == []
    end
  end

  describe "DELETE /api/v1/profiles/me/images/:slot" do
    test "clears the slot and removes the stored file", %{conn: conn, user: user} do
      upload = image_upload(valid_png(), "photo.png")
      conn = post(conn, ~p"/api/v1/profiles/me/images", %{"slot" => "1", "file" => upload})
      assert %{"data" => %{"profile" => %{"images" => images}}} = json_response(conn, 200)
      assert Enum.at(images, 1) =~ "image_"

      conn = delete(conn, ~p"/api/v1/profiles/me/images/1")

      assert %{"data" => %{"profile" => profile}} = json_response(conn, 200)
      assert profile["images"] == ["", ""]
      assert Repo.get!(User, user.id).images == ["", ""]
    end

    test "is idempotent for an empty slot", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/profiles/me/images/3")

      assert %{"data" => %{"profile" => profile}} = json_response(conn, 200)
      assert profile["images"] == []
    end
  end

  describe "PUT /api/v1/profiles/me/images" do
    test "reorders the photos the user already owns", %{conn: conn} do
      first_upload = image_upload(valid_png(), "first.png")
      conn = post(conn, ~p"/api/v1/profiles/me/images", %{"slot" => "0", "file" => first_upload})
      assert %{"data" => %{"profile" => %{"images" => [first]}}} = json_response(conn, 200)

      second_upload = image_upload(valid_png(), "second.png")
      conn = post(conn, ~p"/api/v1/profiles/me/images", %{"slot" => "1", "file" => second_upload})

      assert %{"data" => %{"profile" => %{"images" => [^first, second]}}} =
               json_response(conn, 200)

      conn = put(conn, ~p"/api/v1/profiles/me/images", %{"images" => [second, "", first]})

      assert %{"data" => %{"profile" => %{"images" => [^second, "", ^first]}}} =
               json_response(conn, 200)
    end

    test "rejects filenames the user does not own", %{conn: conn} do
      conn = put(conn, ~p"/api/v1/profiles/me/images", %{"images" => ["someone-else.png"]})

      assert %{"status" => "error", "errors" => errors} = json_response(conn, 422)
      assert errors["images"]
    end

    test "rejects duplicate photos", %{conn: conn} do
      upload = image_upload(valid_png(), "photo.png")
      conn = post(conn, ~p"/api/v1/profiles/me/images", %{"slot" => "0", "file" => upload})
      assert %{"data" => %{"profile" => %{"images" => [filename]}}} = json_response(conn, 200)

      conn = put(conn, ~p"/api/v1/profiles/me/images", %{"images" => [filename, filename]})

      assert %{"status" => "error", "errors" => errors} = json_response(conn, 422)
      assert errors["images"]
    end
  end

  describe "GET /api/v1/profiles/:id" do
    test "returns a public profile for a visible user", %{conn: conn} do
      target = user_fixture(%{first_name: "Grace", bio: "Admiral"})

      conn = get(conn, ~p"/api/v1/profiles/#{target.id}")

      assert %{"data" => %{"profile" => profile}} = json_response(conn, 200)
      assert profile["id"] == target.id
      assert profile["first_name"] == "Grace"
      refute Map.has_key?(profile, "email")
      refute Map.has_key?(profile, "settings")
    end

    test "returns 404 when either party has blocked the other", %{conn: conn, user: user} do
      target = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(target.id, user.id, "block")

      conn = get(conn, ~p"/api/v1/profiles/#{target.id}")
      assert %{"status" => "error"} = json_response(conn, 404)
    end

    test "keeps a muted profile reachable for the management directory", %{conn: conn, user: user} do
      target = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(user.id, target.id, "mute")

      conn = get(conn, ~p"/api/v1/profiles/#{target.id}")
      assert %{"data" => %{"profile" => profile}} = json_response(conn, 200)
      assert profile["id"] == target.id
    end

    test "returns the full profile when viewing yourself", %{conn: conn, user: user} do
      conn = get(conn, ~p"/api/v1/profiles/#{user.id}")

      assert %{"data" => %{"profile" => profile}} = json_response(conn, 200)
      assert profile["id"] == user.id
      assert profile["email"] == user.email
    end
  end

  describe "DELETE /api/v1/profiles/me" do
    test "deactivates the account and revokes its session tokens", %{
      conn: conn,
      user: user,
      token: token
    } do
      conn = delete(conn, ~p"/api/v1/profiles/me")

      assert %{"status" => "success"} = json_response(conn, 200)

      stored = Repo.get!(User, user.id)
      assert stored.user_state == :delete
      refute stored.is_active

      assert is_nil(Accounts.get_user_by_session_token(token))
    end
  end

  describe "GET /api/v1/users/check-handle" do
    test "reports a free valid handle as available", %{conn: conn} do
      conn = get(conn, "/api/v1/users/check-handle?handle=fresh_handle")

      assert %{"available" => true} = json_response(conn, 200)
    end

    test "reports a taken handle as unavailable case-insensitively", %{conn: conn} do
      taken = user_fixture(%{nickname: "taken_handle"})

      conn =
        get(
          conn,
          "/api/v1/users/check-handle?handle=#{String.upcase(taken.nickname)}"
        )

      assert %{"available" => false} = json_response(conn, 200)
    end

    test "reports invalid handles as unavailable", %{conn: conn} do
      for handle <- [
            "bad",
            "1nvalid",
            "has-dash",
            "has space",
            String.duplicate("a", 16)
          ] do
        conn =
          get(
            conn,
            "/api/v1/users/check-handle?handle=#{URI.encode_www_form(handle)}"
          )

        assert %{"available" => false} = json_response(conn, 200)
      end
    end
  end

  describe "PATCH /api/v1/users/me/set-handle" do
    test "assigns a valid unique handle and returns the updated profile", %{
      conn: conn,
      user: user
    } do
      conn =
        patch(conn, ~p"/api/v1/users/me/set-handle", %{
          "handle" => "fresh_handle"
        })

      assert %{
               "status" => "success",
               "data" => %{"profile" => profile}
             } = json_response(conn, 200)

      assert profile["nickname"] == "fresh_handle"
      assert Accounts.get_user!(user.id).nickname == "fresh_handle"
    end

    test "rejects a taken handle case-insensitively", %{conn: conn} do
      _taken = user_fixture(%{nickname: "taken_handle"})

      conn =
        patch(conn, ~p"/api/v1/users/me/set-handle", %{
          "handle" => "TAKEN_HANDLE"
        })

      assert %{
               "status" => "error",
               "code" => "handle_taken",
               "available" => false
             } = json_response(conn, 409)
    end

    test "rejects an invalid handle format", %{conn: conn} do
      conn =
        patch(conn, ~p"/api/v1/users/me/set-handle", %{
          "handle" => "bad"
        })

      assert %{
               "status" => "error",
               "code" => "invalid_handle",
               "available" => false
             } = json_response(conn, 422)
    end

    test "requires authentication" do
      conn =
        build_conn()
        |> patch(~p"/api/v1/users/me/set-handle", %{"handle" => "fresh_handle"})

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/profiles/handle_available/:handle" do
    test "reports a free handle as available", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/profiles/handle_available/unclaimed_handle")

      assert %{"status" => "success", "data" => data} = json_response(conn, 200)
      assert data["handle"] == "unclaimed_handle"
      assert data["available"] == true
      assert data["taken"] == false
    end

    test "reports an existing handle as taken", %{conn: conn} do
      taken = user_fixture(%{nickname: "used_handle"})

      conn = get(conn, ~p"/api/v1/profiles/handle_available/#{taken.nickname}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["available"] == false
      assert data["taken"] == true
    end
  end

  defp valid_png do
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0>>
  end

  defp image_upload(contents, filename) do
    path =
      Path.join(
        System.tmp_dir!(),
        "meetcutes_upload_#{System.unique_integer([:positive])}_#{filename}"
      )

    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    %Plug.Upload{
      path: path,
      filename: filename,
      content_type: "image/png"
    }
  end
end
