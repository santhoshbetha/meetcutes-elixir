defmodule Meetcutes.Surveys.Question do
  use Meetcutes.Schema
  import Ecto.Changeset

  schema "questions" do
    field :text, :string
    field :tier_id, :integer
    field :type, :string
    field :time_limit, :integer
    field :difficulty_weight, :integer

    # Define the structure of an option
    embeds_many :options, Option, on_replace: :delete do
      field :text, :string
      field :points, :integer
    end

    timestamps()
  end

  def changeset(question, attrs) do
    question
    |> cast(attrs, [:text, :tier_id, :type, :time_limit, :difficulty_weight])
    |> cast_embed(:options)
    |> validate_required([:text, :tier_id, :type, :options])
  end
end
