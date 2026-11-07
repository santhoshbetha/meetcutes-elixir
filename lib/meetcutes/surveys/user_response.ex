defmodule Meetcutes.Surveys.UserResponse do
  use Meetcutes.Schema
  import Ecto.Changeset

  schema "user_responses" do
    # 0 for A, 1 for B
    field :choice_index, :integer
    field :points_earned, :integer
    # Useful for detecting bots/cheats
    field :response_time_ms, :integer
    field :changed_answer_count, :integer, default: 0
    # True if this is the final answer for the question
    field :is_final, :boolean, default: true

    belongs_to :user, Meetcutes.Accounts.User
    belongs_to :question, Meetcutes.Surveys.Question

    timestamps()
  end

  def changeset(user_response, attrs) do
    user_response
    |> cast(attrs, [
      :user_id,
      :question_id,
      :choice_index,
      :points_earned,
      :response_time_ms,
      :changed_answer_count,
      :is_final
    ])
    |> validate_required([:user_id, :question_id, :choice_index, :points_earned])
    |> validate_inclusion(:choice_index, 0..1)
    |> validate_number(:points_earned, greater_than_or_equal_to: 0)
    |> validate_number(:response_time_ms, greater_than_or_equal_to: 0)
  end
end
