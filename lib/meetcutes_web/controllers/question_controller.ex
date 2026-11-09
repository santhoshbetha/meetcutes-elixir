defmodule MeetcutesWeb.QuestionController do
  use MeetcutesWeb, :controller
  alias Meetcutes.Surveys
  alias Meetcutes.Repo

  @doc """
  GET /api/quiz/questions
  Fetches 50 randomized and shuffled questions for the logged-in React user.
  """
  def get_random_quiz_set(conn, _params) do
    user = conn.assigns.current_user

    # Fetch 10 random questions from each of the 4 specified tiers
    questions = Surveys.get_random_quiz_set(user.id)

    # Render data through your view/JSON component
    render(conn, :index, questions: questions)
  end

  @doc """
  POST /api/quiz/answers
  Receives the user's choice from React, validates it, and calculates points.
  Expected JSON Body: %{"question_id" => 42, "selected_text" => "$5"}
  """
  def process_answer(conn, %{"question_id" => question_id, "selected_text" => selected_text}) do
    user = conn.assigns.current_user

    # 1. Fetch the absolute true question state safely from Postgres
    question = Repo.get!(Surveys.Question, question_id)

    # 2. Match the string text sent by React back to the database object
    # to extract the points securely, preventing client-side network tampering.
    selected_option = Enum.find(question.options, fn opt -> opt["text"] == selected_text end)

    case selected_option do
      nil ->
        # If the option text didn't match anything in the DB (tampering/bad data)
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid option text submitted."})

      option ->
        # 3. Process the math inside your context transaction
        case Surveys.save_response_and_update_score(user, question, option) do
          {:ok, _response} ->
            conn
            |> put_status(:ok)
            |> json(%{status: "success", message: "Answer recorded successfully."})

          {:error, _changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Could not record answer. Check if already answered."})
        end
    end
  end
end
