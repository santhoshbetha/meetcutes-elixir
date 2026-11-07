defmodule Meetcutes.Repo.Migrations.CreateComments do
  use Ecto.Migration

  def change do
    create table(:comments, primary_key: false) do
      add :id, :string, primary_key: true
      add :content, :text, null: false
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false
      add :event_id, references(:events, type: :string, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:comments, [:user_id])
    create index(:comments, [:event_id])
  end
end
