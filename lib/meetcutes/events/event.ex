defmodule Meetcutes.Events.Event do
  use Meetcutes.Schema
  import Ecto.Changeset

  alias Meetcutes.Accounts.User
  alias Meetcutes.Events.Location

  @statuses ~w(DRAFT PUBLISHED CANCELLED)

  schema "events" do
    field :title, :string
    belongs_to :location, Location
    field :content, :string
    field :start_at, :utc_datetime
    field :end_at, :utc_datetime
    field :event_date, :date
    field :status, :string, default: "DRAFT"
    field :attendees_count, :integer

    # Gender-specific attendance restrictions. All bounds are inclusive.
    field :has_age_restriction, :boolean, default: false
    field :men_min_age, :integer
    field :men_max_age, :integer
    field :women_min_age, :integer
    field :women_max_age, :integer

    # Pre-aggregated demographic counts for detail/list payloads. These are
    # virtual fields populated by the Events context aggregate queries.
    field :male_count, :integer, virtual: true
    field :female_count, :integer, virtual: true

    # Attendees: JSON array of maps, each with user id and gender
    # Example: [%{"user_id" => "...", "gender" => "male"}, ...]
    field :attendees, :map

    # Private fields (never exposed publicly)
    field :internal_notes, :string
    belongs_to :user, User, foreign_key: :created_by

    has_many :comments, Meetcutes.Discussion.Comment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :title,
      :location_id,
      :content,
      :start_at,
      :end_at,
      :event_date,
      :status,
      :attendees_count,
      :internal_notes,
      :created_by,
      :attendees,
      :has_age_restriction,
      :men_min_age,
      :men_max_age,
      :women_min_age,
      :women_max_age
    ])
    |> validate_required([:title, :start_at, :end_at, :location_id])
    |> validate_length(:title, max: 200)
    |> validate_inclusion(:status, @statuses)
    |> validate_age_restriction()
    |> put_event_date()
    |> validate_date_range()
    |> validate_start_in_future()
    |> validate_status_transitions(event)
  end

  @doc """
  Attendance-only changeset.

  Joining/leaving must never re-run event schedule validation (an event that
  has already started can still be joined/left). This changeset deliberately
  only writes the attendee projection and its derived count.
  """
  def attendance_changeset(event, attendees) when is_map(attendees) do
    change(event, %{
      attendees: attendees,
      attendees_count: map_size(attendees)
    })
  end

  defp validate_age_restriction(changeset) do
    if get_field(changeset, :has_age_restriction) do
      changeset
      |> validate_required([:men_min_age, :men_max_age, :women_min_age, :women_max_age])
      |> validate_number(:men_min_age, greater_than_or_equal_to: 18, less_than_or_equal_to: 99)
      |> validate_number(:men_max_age, greater_than_or_equal_to: 18, less_than_or_equal_to: 99)
      |> validate_number(:women_min_age, greater_than_or_equal_to: 18, less_than_or_equal_to: 99)
      |> validate_number(:women_max_age, greater_than_or_equal_to: 18, less_than_or_equal_to: 99)
      |> validate_age_order(:men_min_age, :men_max_age)
      |> validate_age_order(:women_min_age, :women_max_age)
    else
      changeset
    end
  end

  defp validate_age_order(changeset, min_field, max_field) do
    min_age = get_field(changeset, min_field)
    max_age = get_field(changeset, max_field)

    if is_integer(min_age) and is_integer(max_age) and min_age > max_age do
      add_error(changeset, max_field, "must be greater than or equal to the minimum age")
    else
      changeset
    end
  end

  defp validate_date_range(changeset) do
    start_at = get_field(changeset, :start_at)
    end_at = get_field(changeset, :end_at)

    case {start_at, end_at} do
      {nil, _} ->
        changeset

      {_, nil} ->
        changeset

      {start, end_} when start >= end_ ->
        add_error(changeset, :end_at, "must be after start date")

      _ ->
        changeset
    end
  end

  defp validate_start_in_future(changeset) do
    start_at = get_field(changeset, :start_at)

    case start_at do
      nil ->
        changeset

      start when not is_nil(start) ->
        if DateTime.compare(start, DateTime.utc_now()) == :lt do
          add_error(changeset, :start_at, "must be in the future")
        else
          changeset
        end
    end
  end

  defp put_event_date(changeset) do
    case get_field(changeset, :start_at) do
      %DateTime{} = start_at ->
        put_change(changeset, :event_date, DateTime.to_date(start_at))

      _ ->
        changeset
    end
  end

  defp validate_status_transitions(changeset, original_event) do
    new_status = get_change(changeset, :status)
    old_status = original_event.status

    case {old_status, new_status} do
      {nil, _} ->
        # New event, allow any status
        changeset

      {_, nil} ->
        # No status change
        changeset

      {"DRAFT", "PUBLISHED"} ->
        changeset

      {"PUBLISHED", "CANCELLED"} ->
        changeset

      {"DRAFT", "CANCELLED"} ->
        changeset

      {same, same} ->
        changeset

      _ ->
        add_error(
          changeset,
          :status,
          "invalid status transition from #{old_status} to #{new_status}"
        )
    end
  end

  @doc """
  Returns public fields only for public API exposure
  """
  def public_fields(%__MODULE__{} = event) do
    %{
      id: event.id,
      title: event.title,
      start_at: event.start_at,
      end_at: event.end_at,
      event_date: event.event_date,
      status: event.status,
      has_age_restriction: event.has_age_restriction,
      men_min_age: event.men_min_age,
      men_max_age: event.men_max_age,
      women_min_age: event.women_min_age,
      women_max_age: event.women_max_age,
      location: if(event.location, do: Location.public_fields(event.location), else: nil)
    }
  end

  @doc """
  Check if an event is upcoming (start date is in the future)
  """
  def is_upcoming?(%{start_at: start_at}) when not is_nil(start_at) do
    DateTime.compare(start_at, DateTime.utc_now()) == :gt
  end

  @doc """
  Get an event with preloaded comments, user, and location.
  """
  def get_event_with_comments!(id) do
    Meetcutes.Repo.get!(__MODULE__, id)
    |> Meetcutes.Repo.preload([:comments, :user, :location])
  end
end
