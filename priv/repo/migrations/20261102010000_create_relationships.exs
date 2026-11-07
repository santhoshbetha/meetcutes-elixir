defmodule Meetcutes.Repo.Migrations.CreateRelationships do
  use Ecto.Migration

  def change do
    create table(:relationships, primary_key: false) do
      add :id, :string, primary_key: true
      add :actor_id, references(:users, type: :string, on_delete: :delete_all), null: false
      add :target_id, references(:users, type: :string, on_delete: :delete_all), null: false
      add :kind, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:relationships, [:actor_id, :target_id, :kind])
    create index(:relationships, [:target_id, :kind])
    create index(:relationships, [:actor_id, :kind])

    create constraint(:relationships, :relationships_kind_check,
             check: "kind IN ('like', 'block', 'mute')"
           )

    create constraint(:relationships, :relationships_no_self_check,
             check: "actor_id <> target_id"
           )
  end
end
