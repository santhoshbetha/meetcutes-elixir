defmodule Meetcutes.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    create table(:invoices, primary_key: false) do
      add :id, :string, primary_key: true
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false
      add :stripe_charge_id, :string, null: false
      add :amount, :integer, null: false, default: 5000
      add :period_start, :utc_datetime, null: false
      add :period_end, :utc_datetime, null: false
      add :receipt_key, :string
      add :receipt_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invoices, [:stripe_charge_id])
    create index(:invoices, [:user_id])
    create index(:invoices, [:period_end])
  end
end
