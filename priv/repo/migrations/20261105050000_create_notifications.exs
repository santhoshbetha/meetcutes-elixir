defmodule Meetcutes.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :string, primary_key: true
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :title, :string, null: false
      add :body, :text
      add :is_read, :boolean, null: false, default: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:notifications, [:user_id])
    create index(:notifications, [:user_id, :is_read])
    create index(:notifications, [:user_id, :inserted_at])

    create constraint(:notifications, :notifications_type_check,
             check: "type IN ('upcoming_event', 'profile_like', 'admin_broadcast')"
           )
  end
end
