defmodule Meetcutes.Repo.Migrations.AddHideLastNameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :hide_last_name, :boolean, default: false, null: false
    end
  end
end
