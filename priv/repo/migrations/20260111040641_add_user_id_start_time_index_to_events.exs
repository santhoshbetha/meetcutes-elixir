defmodule Meetcutes.Repo.Migrations.AddUserIdStartTimeIndexToEvents do
  use Ecto.Migration

  def change do
    create index(:events, [:created_by, :start_at])
  end
end
