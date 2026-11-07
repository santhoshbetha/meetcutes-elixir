defmodule Meetcutes.Repo.Migrations.AddAgeRestrictionsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :has_age_restriction, :boolean, default: false, null: false
      add :men_min_age, :integer
      add :men_max_age, :integer
      add :women_min_age, :integer
      add :women_max_age, :integer
    end
  end
end
