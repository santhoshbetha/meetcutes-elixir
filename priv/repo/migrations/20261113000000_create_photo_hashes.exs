defmodule Meetcutes.Repo.Migrations.CreatePhotoHashes do
  use Ecto.Migration

  def change do
    create table(:photo_hashes) do
      add :hash, :string, null: false
      add :filename, :string, null: false
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:photo_hashes, [:hash])
    create index(:photo_hashes, [:user_id, :filename])
  end
end
