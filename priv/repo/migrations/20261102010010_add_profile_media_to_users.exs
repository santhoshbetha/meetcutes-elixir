defmodule Meetcutes.Repo.Migrations.AddProfileMediaToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :banner, :map
      add :images, {:array, :string}, default: [], null: false
    end
  end
end
