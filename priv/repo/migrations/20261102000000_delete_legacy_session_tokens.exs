defmodule Meetcutes.Repo.Migrations.DeleteLegacySessionTokens do
  use Ecto.Migration

  # Session tokens are now stored as SHA-256 hashes. Rows created before that
  # change hold the raw (Base64 encoded) token, which can no longer be
  # verified, so remove them instead of leaving the plaintext secrets around.
  def up do
    execute "DELETE FROM users_tokens WHERE context = 'session'"
  end

  def down do
    :ok
  end
end
