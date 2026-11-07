defmodule Meetcutes.Surveys do
  @moduledoc """
  The Surveys context.
  """
  import Ecto.Query, warn: false
  alias Meetcutes.Repo

  alias Meetcutes.Accounts.User
  alias Meetcutes.Surveys.{Question, UserResponse}

  @doc """
  Returns the list of questions.

  ## Examples

      iex> list_questions()
      [%Question{}, ...]

  """
  def list_questions do
    Repo.all(Question)
  end

  @doc """
  Gets a single question.

  Raises `Ecto.NoResultsError` if the Question does not exist.

  ## Examples

      iex> get_question!(123)
      %Question{}

      iex> get_question!(456)
      ** (Ecto.NoResultsError)

  """
  def get_question!(id), do: Repo.get!(Question, id)

  @doc """
  Creates a question.

  ## Examples

      iex> create_question(%{field: value})
      {:ok, %Question{}}

      iex> create_question(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_question(attrs \\ %{}) do
    %Question{}
    |> Question.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a question.

  ## Examples

      iex> update_question(question, %{field: new_value})
      {:ok, %Question{}}

      iex> update_question(question, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_question(%Question{} = question, attrs) do
    question
    |> Question.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a question.

  ## Examples

      iex> delete_question(question)
      {:ok, %Question{}}

      iex> delete_question(question)
      {:error, %Ecto.Changeset{}}

  """
  def delete_question(%Question{} = question) do
    Repo.delete(question)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking question changes.

  ## Examples

      iex> change_question(question)
      %Ecto.Changeset{data: %Question{}}

  """
  def change_question(%Question{} = question, attrs \\ %{}) do
    Question.changeset(question, attrs)
  end

  @doc """
  Returns questions filtered by tier_id.

  ## Examples

      iex> list_questions_by_tier(1)
      [%Question{}, ...]

  """
  def list_questions_by_tier(tier_id) do
    Question
    |> where([q], q.tier_id == ^tier_id)
    |> Repo.all()
  end

  def get_random_questions_for_user(user_id, limit \\ 20) do
    # Get IDs of questions already answered
    answered_ids =
      from(r in Meetcutes.Surveys.UserResponse,
        where: r.user_id == ^user_id,
        select: r.question_id
      )
      |> Repo.all()

    # Get random pool excluding answered ones
    from(q in Question,
      where: q.id not in ^answered_ids,
      order_by: fragment("RANDOM()"),
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Fetches 50 random questions total (10 from each specified Tier) that the user
  has not answered yet, shuffling the multiple-choice options to prevent cheating.
  """
  def get_random_quiz_set(user_id, count_per_tier \\ 10) do
    # 1. Get a list of IDs for all questions this user has already answered
    answered_ids_query =
      from(r in UserResponse,
        where: r.user_id == ^user_id,
        select: r.question_id
      )

    answered_ids = Repo.all(answered_ids_query)

    # 2. Define the Tiers you want to fetch from
    # (1: Integrity, 2: Stewardship, 3: Cognitive/IQ, 5: Narcissism)
    tiers = [1, 2, 3, 5]

    # 3. For each tier, pull a random subset of unanswered questions
    questions =
      Enum.flat_map(tiers, fn tier_id ->
        from(q in Question,
          where: q.tier_id == ^tier_id,
          where: q.id not in ^answered_ids,
          order_by: fragment("RANDOM()"),
          limit: ^count_per_tier
        )
        |> Repo.all()
      end)

    # 4. Anti-Cheat: Shuffle the multiple-choice options in memory
    # so React receives them in a completely unpredictable order.
    Enum.map(questions, fn question ->
      shuffled_options = Enum.shuffle(question.options)
      Map.put(question, :options, shuffled_options)
    end)
  end

  def process_answer(user, question, choice_index) do
    # choice_index is 0 for A, 1 for B
    selected_option = Enum.at(question.options, choice_index)
    points = selected_option.points * question.difficulty_weight

    Repo.transaction(fn ->
      # 1. Save the response
      %UserResponse{
        user_id: user.id,
        question_id: question.id,
        points_earned: points
      }
      |> Repo.insert!()

      # 2. Update the specific user score based on tier_id
      column =
        case question.tier_id do
          1 -> :integrity_score
          2 -> :stewardship_score
          3 -> :cognitive_score
          4 -> :lifestyle_score
          5 -> :empathy_score
        end

      new_total = Map.get(user, column) + points

      user
      |> Ecto.Changeset.change(%{column => new_total})
      |> Repo.update!()
    end)
  end

  @doc """
  Saves a user's quiz answer and updates their hidden archetype scores
  inside an atomic database transaction.
  """
  def save_response_and_update_score(
        %User{} = user,
        %Question{} = question,
        %{} = selected_option
      ) do
    # 1. Extract the raw points from the matched JSONB option map
    raw_points = Map.get(selected_option, "points", 0)

    # 2. Multiply by difficulty weight (e.g., higher weights for Tier 3 / IQ)
    points_earned = raw_points * question.difficulty_weight

    Repo.transaction(fn ->
      # 3. Build and insert the UserResponse record
      response_attrs = %{
        user_id: user.id,
        question_id: question.id,
        choice_text: Map.get(selected_option, "text"),
        points_earned: points_earned
      }

      response =
        %UserResponse{}
        |> UserResponse.changeset(response_attrs)
        # Triggers unique constraint error if double-submitted
        |> Repo.insert!()

      # 4. Map the question's Tier ID to the correct column on the users table
      score_field =
        case question.tier_id do
          1 -> :integrity_score
          2 -> :stewardship_score
          3 -> :cognitive_score
          4 -> :lifestyle_score
          # Triggers for the custom Narcissism tier
          5 -> :empathy_score
        end

      # 5. Fetch the current field value and calculate the new sum
      current_score = Map.get(user, score_field) || 0
      new_score = current_score + points_earned

      # 6. Update the user row directly in the database
      user
      |> Ecto.Changeset.change(%{score_field => new_score})
      |> Repo.update!()

      # Return the response record on transactional success
      response
    end)
  end
end
