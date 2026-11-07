defmodule Meetcutes.Repo.Migrations.CreateLocations do
  use Ecto.Migration

  def change do
    create table(:locations, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :url, :string
      add :longitude, :float
      add :latitude, :float
      add :street, :string
      add :postal_code, :string
      add :locality, :string
      add :region, :string
      add :state, :string
      add :country, :string

      timestamps(type: :utc_datetime)
    end

    create index(:locations, [:name])
  end
end
