defmodule Meetcutes.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users, primary_key: false) do
      add :id, :string, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      add :nickname, :string
      add :avatar, :map
      add :first_name, :string
      add :last_name, :string
      add :gender, :string
      add :age, :integer
      add :city, :string
      add :state, :string
      add :phone_number, :string
      add :facebook, :string
      add :instagram, :string
      add :linkedin, :string
      add :birth_year, :integer
      add :bio, :string, default: "", null: false
      add :geohash, :string
      add :default_coords_set, :boolean
      add :user_coords_set, :boolean
      add :exact_coords_set, :boolean
      add :email_search, :boolean
      add :phone_number_search, :boolean
      add :user_handle_search, :boolean
      add :only_hundred_miles_visibility, :boolean
      add :date_of_location, :utc_datetime
      add :date_of_coordinates, :utc_datetime
      add :time_of_login, :utc_datetime
      add :last_login_at, :utc_datetime
      add :last_seen_at, :utc_datetime
      add :last_active_at, :naive_datetime
      add :last_refreshed_at, :naive_datetime_usec
      add :questionaire_values, :map
      add :questionaire_values_set, :boolean
      add :onetime_fees_paid, :boolean
      add :onetime_fees_required, :boolean
      add :accepted_onetime_fees_amount, :integer
      add :user_state, :string
      add :email_verified, :boolean
      add :previous_events_attendees_list, {:array, :string}
      add :registered_events, {:array, :map}
      add :created_events, {:array, :map}
      add :previous_events_attendees_date, :utc_datetime
      add :password_retry_count, :integer
      add :id_verified, :boolean
      add :settings, :map
      add :uri, :string
      add :calendar_token, :string, null: false
      add :time_zone, :string, default: "UTC", null: false
      add :is_active, :boolean, default: true, null: false
      add :is_locked, :boolean, default: false, null: false
      add :is_approved, :boolean, default: true, null: false
      add :is_confirmed, :boolean, default: false, null: false
      add :invisible, :boolean, default: false, null: false
      add :notification_settings, :map, default: %{}, null: false
      add :password_reset_pending, :boolean, default: false, null: false
      add :deactivated, :boolean, default: false, null: false
      add :approval_pending, :boolean, default: false, null: false
      add :confirmation_pending, :boolean, default: false, null: false
      add :terms_accepted, :boolean
      add :deleted_at, :utc_datetime
      add :integrity_score, :integer, default: 0, null: false
      add :stewardship_score, :integer, default: 0, null: false
      add :cognitive_score, :integer, default: 0, null: false
      add :lifestyle_score, :integer, default: 0, null: false
      add :overall_percentile, :float, default: 0.0, null: false
      add :completed_quiz, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:calendar_token])
    create index(:users, [:phone_number])
    create index(:users, [:email, :deleted_at])
    create index(:users, [:geohash])

    create table(:users_tokens, primary_key: false) do
      add :id, :string, primary_key: true
      add :user_id, references(:users, type: :string, on_delete: :delete_all), null: false
      add :token, :text, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
