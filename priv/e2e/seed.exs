# Idempotent E2E seed data.
#
# Run with:
#
#     mix run priv/e2e/seed.exs
#
# The script reuses existing rows by email, so it is safe to run before every
# Playwright suite. It also resets relationships and profile state that the
# tests mutate (settings, avatars, deactivation).

import Ecto.Query

alias Meetcutes.Accounts
alias Meetcutes.Accounts.UserToken
alias Meetcutes.Events.Event
alias Meetcutes.Notifications
alias Meetcutes.Relationships.Relationship
alias Meetcutes.Repo

password = "E2ePassword123!"
austin = {30.2672, -97.7431}
geohash = Geohash.encode(elem(austin, 0), elem(austin, 1), 9)

now = DateTime.utc_now() |> DateTime.truncate(:second)
naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

seed_users = [
  %{
    key: :viewer,
    email: "e2e.viewer@meetcutes.test",
    nickname: "e2e_viewer",
    first_name: "E2EViewer",
    gender: "Male",
    phone_number: "5125550101"
  },
  %{
    key: :feed_viewer,
    email: "e2e.feedviewer@meetcutes.test",
    nickname: "e2e_feedviewer",
    first_name: "E2EFeedViewer",
    gender: "Female",
    phone_number: "5125550102"
  },
  %{
    key: :mute_target,
    email: "e2e.mute.target@meetcutes.test",
    nickname: "e2e_mute_target",
    first_name: "MuteTarget",
    gender: "Male",
    phone_number: "5125550103"
  },
  %{
    key: :block_target,
    email: "e2e.block.target@meetcutes.test",
    nickname: "e2e_block_target",
    first_name: "BlockTarget",
    gender: "Male",
    phone_number: "5125550104"
  },
  %{
    key: :deactivate_user,
    email: "e2e.deactivate@meetcutes.test",
    nickname: "e2e_deactivate",
    first_name: "DeactivateUser",
    gender: "Female",
    phone_number: "5125550105"
  },
  %{
    key: :email_change,
    email: "e2e.emailchange@meetcutes.test",
    nickname: "e2e_emailchange",
    first_name: "EmailChange",
    gender: "Female",
    phone_number: "5125550106"
  },
  %{
    key: :paywall,
    email: "e2e.paywall@meetcutes.test",
    nickname: "e2e_paywall",
    first_name: "Paywall",
    gender: "Male",
    phone_number: "5125550107",
    around_user_count: 205,
    around_user_count_updated_at: now,
    subscription_expires_at: nil,
    stripe_customer_id: "cus_e2e_paywall"
  }
]

upsert = fn attrs ->
  user =
    case Accounts.get_user_by_email(attrs.email) do
      nil ->
        {:ok, user} =
          Accounts.register_user(%{
            email: attrs.email,
            password: password,
            password_confirmation: password,
            first_name: attrs.first_name,
            last_name: "E2E",
            nickname: attrs.nickname,
            gender: attrs.gender,
            age: 30,
            city: "Austin",
            state: "TX",
            phone_number: attrs.phone_number,
            time_zone: "America/Chicago",
            settings: %{"visibility_preference" => "both"}
          })

        user

      user ->
        user
    end

  changeset =
    Ecto.Changeset.change(user,
      confirmed_at: now,
      is_confirmed: true,
      email_verified: true,
      confirmation_pending: false,
      user_state: :active,
      is_active: true,
      is_approved: true,
      is_locked: false,
      terms_accepted: true,
      deleted_at: nil,
      geohash: geohash,
      gender: attrs.gender,
      age: 30,
      birth_year: 1996,
      city: "Austin",
      state: "TX",
      nickname: attrs.nickname,
      first_name: attrs.first_name,
      last_name: "E2E",
      settings: %{"visibility_preference" => "both"},
      email_search: true,
      phone_number_search: true,
      user_handle_search: true,
      only_hundred_miles_visibility: false,
      avatar: nil,
      images: [],
      time_of_login: now,
      last_login_at: now,
      last_seen_at: now,
      last_active_at: naive_now,
      around_user_count: Map.get(attrs, :around_user_count, 0),
      around_user_count_updated_at: Map.get(attrs, :around_user_count_updated_at),
      subscription_expires_at: Map.get(attrs, :subscription_expires_at),
      stripe_customer_id: Map.get(attrs, :stripe_customer_id),
      password_retry_count: 0,
      password_reset_pending: false
    )

  {:ok, updated} = Repo.update(changeset)
  updated
end

# The email-change spec mutates this fixture's address, so restore the
# canonical email before the idempotent upsert looks the account up by email.
email_change_target = "e2e.emailchange.new@meetcutes.test"

Repo.update_all(
  from(u in Meetcutes.Accounts.User,
    where: u.nickname == "e2e_emailchange" and u.email != "e2e.emailchange@meetcutes.test"
  ),
  set: [email: "e2e.emailchange@meetcutes.test"]
)

seeded =
  Map.new(seed_users, fn attrs ->
    user = upsert.(attrs)
    {attrs.key, user}
  end)

user_ids = seeded |> Map.values() |> Enum.map(& &1.id)

# Remove invoices created by the billing webhook spec so every suite starts
# with a clean subscription state.
Repo.delete_all(
  from i in Meetcutes.Billing.Invoice,
    where: i.user_id in ^user_ids
)

# Reset every relationship that involves a seed user so each run starts clean.
Repo.delete_all(
  from r in Relationship,
    where: r.actor_id in ^user_ids or r.target_id in ^user_ids
)

# Clear stale sessions for the seed accounts.
Repo.delete_all(
  from t in UserToken,
    where:
      t.user_id in ^user_ids and
        (t.context in ["session", "reset_password"] or like(t.context, "change:%"))
)

# Rebuild a deterministic inbox for the notification specs. The viewer gets
# one item of each supported type; the feed viewer gets its own isolated set so
# API assertions never race the UI assertions.
Repo.delete_all(
  from n in Meetcutes.Notifications.Notification,
    where: n.user_id in ^user_ids
)

viewer_for_notifications = Map.fetch!(seeded, :viewer)
feed_viewer_for_notifications = Map.fetch!(seeded, :feed_viewer)

notification_seed = [
  {viewer_for_notifications,
   [
     %{
       type: :upcoming_event,
       title: "Coffee & Conversation is near you",
       body:
         "A new meetup is happening within 50 miles this week. Save your spot before it fills up.",
       metadata: %{
         "event_id" => "e2e-notification-event",
         "event_title" => "Coffee & Conversation"
       }
     },
     %{
       type: :profile_like,
       title: "Someone liked your profile",
       body: "A nearby member added you to their shortlist. See who is interested.",
       metadata: %{
         "sender_id" => feed_viewer_for_notifications.id,
         "sender_handle" => feed_viewer_for_notifications.nickname
       }
     },
     %{
       type: :admin_broadcast,
       title: "Welcome to your new inbox",
       body: "Events, likes, and announcements now live in one calm, centralized feed.",
       metadata: %{}
     }
   ]},
  {feed_viewer_for_notifications,
   [
     %{
       type: :upcoming_event,
       title: "Weekend social is filling up",
       body: "A nearby event is almost at capacity.",
       metadata: %{"event_id" => "e2e-notification-event-2"}
     },
     %{
       type: :profile_like,
       title: "A new admirer",
       body: "Someone across town liked your profile.",
       metadata: %{"sender_id" => viewer_for_notifications.id}
     },
     %{
       type: :admin_broadcast,
       title: "Profile tips from the team",
       body: "Add a recent photo to make a stronger first impression.",
       metadata: %{}
     }
   ]}
]

Enum.each(notification_seed, fn {user, notifications} ->
  Enum.each(notifications, fn attrs ->
    {:ok, _notification} =
      attrs
      |> Map.put(:user_id, user.id)
      |> Notifications.create_notification()
  end)
end)

# Generate a fresh email-change token so the Playwright spec can walk the
# confirmation link without needing access to the mailbox.
email_change_user = Map.fetch!(seeded, :email_change)
{:ok, token_agent} = Agent.start_link(fn -> nil end)

{:ok, _email} =
  Accounts.deliver_user_update_email_instructions(
    %{email_change_user | email: email_change_target},
    email_change_user.email,
    fn token ->
      Agent.update(token_agent, fn _ -> token end)
      token
    end
  )

email_change_token = Agent.get(token_agent, & &1)
Agent.stop(token_agent)

File.write!(
  Path.join(System.tmp_dir!(), "meetcutes-e2e-email-change-token"),
  email_change_token
)

# Publish a fresh reset token so the `/auth/confirm` Playwright spec can walk
# the recovery link without needing access to the mailbox.
viewer = Map.fetch!(seeded, :viewer)
{reset_token, reset_user_token} = UserToken.build_email_token(viewer, "reset_password")
Repo.insert!(reset_user_token)
File.write!(Path.join(System.tmp_dir!(), "meetcutes-e2e-reset-token"), reset_token)

# Remove events created by the seed accounts so event tests start from a clean
# slate and location/time conflicts do not leak between runs.
Repo.delete_all(
  from e in Event,
    where: e.created_by in ^user_ids
)

IO.puts("\nE2E seed ready (password: #{password}):")

Enum.each(seed_users, fn attrs ->
  user = Map.fetch!(seeded, attrs.key)

  IO.puts("  #{attrs.key}: id=#{user.id} email=#{user.email} handle=#{user.nickname}")
end)
