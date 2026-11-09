defmodule Meetcutes.Accounts.UserNotifierTest do
  use Meetcutes.DataCase, async: false

  import Meetcutes.AccountsFixtures

  alias Meetcutes.Accounts.UserNotifier
  alias Meetcutes.Emails.Layout

  describe "deliver_reset_password_instructions/2" do
    test "renders the branded HTML reset email and keeps the link on the frontend" do
      user = user_fixture(%{first_name: "Avery"})
      reset_url = "https://meetcutes.us/changepassword?token=reset-token"

      assert {:ok, email} = UserNotifier.deliver_reset_password_instructions(user, reset_url)

      assert email.from == {"Meetcutes", "noreply@meetcutes.us"}
      assert email.subject == "Reset your Meetcutes password"
      assert email.text_body =~ "Hi Avery"
      assert email.text_body =~ reset_url

      assert email.html_body =~ "Reset your Meetcutes password"
      assert email.html_body =~ "Hi Avery"
      assert email.html_body =~ reset_url
      assert email.html_body =~ "Reset my password"
      refute email.html_body =~ "/api/"
    end

    test "normalises relative reset links against the frontend origin" do
      user = user_fixture(%{first_name: "Avery"})

      assert {:ok, email} =
               UserNotifier.deliver_reset_password_instructions(
                 user,
                 "/changepassword?token=relative-token"
               )

      assert email.html_body =~ "https://meetcutes.us/changepassword?token=relative-token"

      assert Layout.ensure_absolute_url("/changepassword") ==
               "https://meetcutes.us/changepassword"
    end
  end
end
