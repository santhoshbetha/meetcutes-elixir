defmodule Meetcutes.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Meetcutes.Accounts` context.
  """

  import Ecto.Query

  alias Meetcutes.Accounts

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def unique_user_phone do
    suffix =
      System.unique_integer([:positive])
      |> rem(10_000_000)
      |> Integer.to_string()
      |> String.pad_leading(7, "0")

    "555" <> suffix
  end

  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      first_name: "John",
      last_name: "Doe",
      phone_number: unique_user_phone()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user
  end

  def set_password(user) do
    {:ok, user} = Accounts.reset_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    {:ok, hashed_token} = Accounts.UserToken.hash_session_token(token)

    Meetcutes.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^hashed_token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Meetcutes.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Meetcutes.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
