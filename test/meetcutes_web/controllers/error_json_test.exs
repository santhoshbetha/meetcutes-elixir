defmodule MeetcutesWeb.ErrorJSONTest do
  use MeetcutesWeb.ConnCase, async: true

  test "renders not_found" do
    assert MeetcutesWeb.ErrorJSON.not_found() == %{
             status: "error",
             message: "Resource lookup failed.",
             errors: ["Resource not found"]
           }
  end

  test "renders unauthorized" do
    assert MeetcutesWeb.ErrorJSON.unauthorized() == %{
             status: "error",
             message: "Authentication failed.",
             errors: ["Invalid or missing authentication token"]
           }
  end

  test "renders forbidden" do
    assert MeetcutesWeb.ErrorJSON.forbidden() == %{
             status: "error",
             message: "Permission denied.",
             errors: ["Access denied"]
           }
  end

  test "renders bad_request" do
    assert MeetcutesWeb.ErrorJSON.bad_request() == %{
             status: "error",
             message: "Invalid request.",
             errors: ["Invalid request parameters"]
           }
  end

  test "renders unprocessable_entity" do
    assert MeetcutesWeb.ErrorJSON.unprocessable_entity() == %{
             status: "error",
             message: "Validation failed.",
             errors: ["The request contains invalid entity attributes"]
           }
  end

  test "renders error with changeset" do
    changeset = %Ecto.Changeset{
      valid?: false,
      errors: [email: {"can't be blank", [validation: :required]}],
      data: %{}
    }

    result = MeetcutesWeb.ErrorJSON.error(%{changeset: changeset})
    assert result[:status] == "error"
    assert result[:message] == "Validation failed"
    assert is_map(result[:errors])
  end

  test "renders error with message" do
    result = MeetcutesWeb.ErrorJSON.error(%{error: "Something went wrong"})

    assert result == %{
             status: "error",
             message: "An error occurred",
             errors: ["Something went wrong"]
           }
  end
end
