defmodule Meetcutes.Repo.Migrations.CreateQuestions do
  use Ecto.Migration

  def change do
    create table(:questions, primary_key: false) do
      add :id, :string, primary_key: true
      add :text, :string
      add :tier_id, :integer
      add :type, :string
      add :time_limit, :integer
      add :difficulty_weight, :integer
      add :options, :map

      timestamps()
    end

    create index(:questions, [:tier_id])
  end
end
