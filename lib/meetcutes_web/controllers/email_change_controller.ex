defmodule MeetcutesWeb.EmailChangeController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Accounts

  @doc """
  Confirms an email change using the token from the confirmation email.

  This endpoint is intentionally unauthenticated: the link is opened from a
  mailbox and may not be in the same browser that requested the change. The
  token is single-use, expires after seven days, and is only valid for the
  user's current email address.

  Only the new email address is returned so the endpoint does not expose the
  rest of the profile to anyone holding a forwarded link.
  """
  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_email_change(token) do
      {:ok, user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          status: "success",
          message: "Email has been updated successfully",
          email: user.email
        })

      :error ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", message: "Email change link is invalid or it has expired."})
    end
  end
end
