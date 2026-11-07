defmodule Meetcutes.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :string, primary_key: true
      add :title, :string, null: false
      add :location_id, references(:locations, type: :string, on_delete: :nilify_all), null: false
      add :content, :text
      add :start_at, :utc_datetime, null: false
      add :end_at, :utc_datetime, null: false
      add :event_date, :date
      add :status, :string, default: "DRAFT"
      add :attendees_count, :integer
      add :attendees, :map
      add :internal_notes, :text
      add :created_by, references(:users, type: :string, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:location_id])
    create index(:events, [:created_by])
  end
end
