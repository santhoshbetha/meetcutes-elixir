defmodule Meetcutes.Workers.NotificationWorkerTest do
  use Meetcutes.DataCase, async: false
  use Oban.Testing, repo: Meetcutes.Repo

  import Meetcutes.AccountsFixtures
  import Swoosh.TestAssertions

  alias Meetcutes.Workers.{MailerWorker, NotificationWorker}

  describe "deliver_match_reminder/2" do
    test "renders the branded reminder and sends through the test adapter" do
      target = user_fixture(%{first_name: "Taylor"})
      matched = user_fixture(%{first_name: "Jordan"})

      assert :ok = MailerWorker.deliver_match_reminder(target, matched)

      assert_email_sent(fn email ->
        assert email.to == [{"", target.email}]
        assert email.from == {"Meetcutes", "noreply@meetcutes.us"}
        assert email.subject == "Someone new is waiting for you on Meetcutes"
        assert email.text_body =~ "Hi Taylor"
        assert email.text_body =~ "Austin discovery pool"
        assert email.html_body =~ "Austin discovery pool"
        assert email.html_body =~ "Click here"
        assert email.html_body =~ "https://meetcutes.us/user/#{matched.id}"
      end)
    end
  end

  describe "perform/1" do
    test "loads both profiles and delivers the reminder" do
      target = user_fixture(%{first_name: "Avery"})
      matched = user_fixture(%{first_name: "Morgan"})

      assert :ok =
               perform_job(NotificationWorker, %{
                 user_id: target.id,
                 match_id: matched.id,
                 action: "match_reminder"
               })

      assert_email_sent(fn email ->
        assert email.to == [{"", target.email}]
        assert email.html_body =~ "https://meetcutes.us/user/#{matched.id}"
      end)
    end

    test "cancels when the recipient no longer exists" do
      matched = user_fixture()

      assert {:cancel, :profile_not_found} =
               perform_job(NotificationWorker, %{
                 user_id: "missing-user-id",
                 match_id: matched.id,
                 action: "match_reminder"
               })
    end

    test "cancels unsupported actions" do
      assert {:cancel, {:unsupported_action, "unknown"}} =
               perform_job(NotificationWorker, %{action: "unknown"})
    end
  end
end
