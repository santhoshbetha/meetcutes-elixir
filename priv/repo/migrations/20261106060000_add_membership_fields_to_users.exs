defmodule Meetcutes.Repo.Migrations.AddMembershipFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :around_user_count, :integer, null: false, default: 0
      add :around_user_count_updated_at, :utc_datetime
      add :subscription_expires_at, :utc_datetime
      add :stripe_customer_id, :string
    end

    create index(:users, [:around_user_count])
    create index(:users, [:subscription_expires_at])
  end
end
