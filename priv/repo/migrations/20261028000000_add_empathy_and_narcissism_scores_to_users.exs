defmodule Meetcutes.Repo.Migrations.AddEmpathyAndNarcissismScoresToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :empathy_score, :integer, default: 0, null: false
      add :narcissism_flags, :integer, default: 0, null: false
    end
  end
end
