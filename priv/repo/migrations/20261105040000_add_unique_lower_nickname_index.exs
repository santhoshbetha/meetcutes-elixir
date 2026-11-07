defmodule Meetcutes.Repo.Migrations.AddUniqueLowerNicknameIndex do
  use Ecto.Migration

  def change do
    create unique_index(:users, ["lower(nickname)"],
             name: :users_lower_nickname_index,
             where: "nickname IS NOT NULL AND deleted_at IS NULL"
           )
  end
end
