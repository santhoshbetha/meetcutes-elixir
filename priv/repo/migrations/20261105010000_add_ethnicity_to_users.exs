defmodule Meetcutes.Repo.Migrations.AddEthnicityToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :ethnicity, :string
    end
  end
end
