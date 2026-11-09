defmodule Meetcutes.RelationshipsTest do
  use Meetcutes.DataCase
  use Oban.Testing, repo: Meetcutes.Repo

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Relationships
  alias Meetcutes.Workers.NotificationWorker

  describe "create_relationship/3" do
    test "creates a like, block, and mute" do
      actor = user_fixture()
      target = user_fixture()

      assert {:ok, like} = Relationships.create_relationship(actor.id, target.id, "like")
      assert like.kind == :like
      assert like.actor_id == actor.id
      assert like.target_id == target.id

      assert {:ok, block} = Relationships.create_relationship(actor.id, target.id, "block")
      assert block.kind == :block

      other = user_fixture()
      assert {:ok, mute} = Relationships.create_relationship(actor.id, other.id, :mute)
      assert mute.kind == :mute
    end

    test "is idempotent for repeated likes" do
      actor = user_fixture()
      target = user_fixture()

      assert {:ok, first} = Relationships.create_relationship(actor.id, target.id, "like")
      assert {:ok, second} = Relationships.create_relationship(actor.id, target.id, "like")
      assert first.id == second.id
    end

    test "rejects self relationships" do
      user = user_fixture()

      assert {:error, :self_relationship} =
               Relationships.create_relationship(user.id, user.id, "like")
    end

    test "rejects unknown kinds" do
      actor = user_fixture()
      target = user_fixture()

      assert {:error, :invalid_kind} =
               Relationships.create_relationship(actor.id, target.id, "follow")
    end

    test "rejects missing targets" do
      actor = user_fixture()

      assert {:error, :target_not_found} =
               Relationships.create_relationship(actor.id, Ecto.ULID.generate(), "like")
    end

    test "rejects a like when either party has blocked the other" do
      actor = user_fixture()
      target = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(target.id, actor.id, "block")
      assert {:error, :blocked} = Relationships.create_relationship(actor.id, target.id, "like")
    end
  end

  describe "blocking and muting" do
    test "blocking removes likes in both directions and the actor's mute" do
      actor = user_fixture()
      target = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(actor.id, target.id, "like")
      assert {:ok, _} = Relationships.create_relationship(target.id, actor.id, "like")
      assert Relationships.summary(actor.id).matches == [target.id]

      assert {:ok, _} = Relationships.create_relationship(actor.id, target.id, "mute")
      assert Relationships.summary(actor.id).likes == []

      assert {:ok, _} = Relationships.create_relationship(actor.id, target.id, "block")

      summary = Relationships.summary(actor.id)
      assert summary.likes == []
      assert summary.mutes == []
      assert summary.blocks == [target.id]
      assert Relationships.summary(target.id).likes == []
    end

    test "muting removes the actor's outgoing like" do
      actor = user_fixture()
      target = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(actor.id, target.id, "like")
      assert {:ok, _} = Relationships.create_relationship(actor.id, target.id, "mute")

      summary = Relationships.summary(actor.id)
      assert summary.likes == []
      assert summary.mutes == [target.id]
    end

    test "hidden? is symmetric" do
      actor = user_fixture()
      target = user_fixture()

      refute Relationships.hidden?(actor.id, target.id)
      assert {:ok, _} = Relationships.create_relationship(actor.id, target.id, "mute")

      assert Relationships.hidden?(actor.id, target.id)
      assert Relationships.hidden?(target.id, actor.id)
    end
  end

  describe "delete_relationship/3" do
    test "removes a relationship and is idempotent" do
      actor = user_fixture()
      target = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(actor.id, target.id, "block")
      assert {:ok, :block} = Relationships.delete_relationship(actor.id, target.id, "block")
      refute Relationships.hidden?(actor.id, target.id)

      assert {:ok, :block} = Relationships.delete_relationship(actor.id, target.id, "block")
    end
  end

  describe "summary/1" do
    test "derives matches from mutual likes" do
      actor = user_fixture()
      target = user_fixture()
      stranger = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(actor.id, target.id, "like")
      assert {:ok, _} = Relationships.create_relationship(target.id, actor.id, "like")
      assert {:ok, _} = Relationships.create_relationship(actor.id, stranger.id, "like")

      summary = Relationships.summary(actor.id)
      assert Enum.sort(summary.likes) == Enum.sort([target.id, stranger.id])
      assert summary.matches == [target.id]
    end
  end

  describe "match reminders" do
    test "enqueues one reminder for each side when a mutual like is created" do
      actor = user_fixture()
      target = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(actor.id, target.id, "like")
      refute_enqueued(worker: NotificationWorker)

      assert {:ok, _} = Relationships.create_relationship(target.id, actor.id, "like")

      assert_enqueued(
        worker: NotificationWorker,
        args: %{user_id: actor.id, match_id: target.id, action: "match_reminder"}
      )

      assert_enqueued(
        worker: NotificationWorker,
        args: %{user_id: target.id, match_id: actor.id, action: "match_reminder"}
      )
    end

    test "does not enqueue for a repeated or one-way like" do
      actor = user_fixture()
      target = user_fixture()

      assert {:ok, _} = Relationships.create_relationship(actor.id, target.id, "like")
      assert {:ok, _} = Relationships.create_relationship(actor.id, target.id, "like")

      refute_enqueued(worker: NotificationWorker)
    end
  end
end
