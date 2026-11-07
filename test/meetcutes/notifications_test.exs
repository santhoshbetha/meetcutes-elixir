defmodule Meetcutes.NotificationsTest do
  use Meetcutes.DataCase, async: false

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Notifications
  alias MeetcutesWeb.Endpoint

  describe "create_notification/1" do
    test "persists the row and broadcasts it to the owner's personal channel" do
      user = user_fixture()

      :ok = Endpoint.subscribe("user_notifications:#{user.id}")

      assert {:ok, notification} =
               Notifications.create_notification(%{
                 user_id: user.id,
                 type: :profile_like,
                 title: "Someone liked your profile",
                 body: "A nearby member added you to their shortlist.",
                 metadata: %{"sender_id" => Ecto.ULID.generate()}
               })

      assert_receive %Phoenix.Socket.Broadcast{
                       topic: topic,
                       event: "new_notification",
                       payload: payload
                     },
                     500

      assert topic == "user_notifications:#{user.id}"
      assert payload.id == notification.id
      assert payload.type == "profile_like"
      assert payload.title == "Someone liked your profile"
      assert payload.is_read == false
      assert payload.metadata == %{"sender_id" => notification.metadata["sender_id"]}
    end

    test "does not broadcast when the row fails validation" do
      user = user_fixture()

      :ok = Endpoint.subscribe("user_notifications:#{user.id}")

      assert {:error, changeset} =
               Notifications.create_notification(%{
                 user_id: user.id,
                 type: :profile_like,
                 title: nil
               })

      refute changeset.valid?
      refute_receive %Phoenix.Socket.Broadcast{event: "new_notification"}, 200
    end
  end
end
