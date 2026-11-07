defmodule MeetcutesWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint/fallback controller in case of errors on JSON requests.
  """
  alias Ecto.Changeset

  # -----------------------------------------------------------
  # 1. Native Phoenix 1.7+ Standard Error Templates
  # -----------------------------------------------------------

  # Phoenix automatically passes status strings like "404.json" to render/2.
  def render(template, _assigns) do
    case normalize_template(template) do
      "400" ->
        bad_request()

      "401" ->
        unauthorized()

      "403" ->
        forbidden()

      "404" ->
        not_found()

      "422" ->
        unprocessable_entity()

      "500" ->
        internal_server_error()

      other ->
        %{
          status: "error",
          message: "An error occurred.",
          errors: [Phoenix.Naming.humanize(other)]
        }
    end
  end

  # -----------------------------------------------------------
  # 2. Custom Controller Direct Invocation Helpers (Backwards Compatibility)
  # -----------------------------------------------------------

  @doc """
  Directly converts a complex changeset into your unified React app error array tree format.
  """
  def error(%{changeset: %Changeset{} = changeset}) do
    %{
      status: "error",
      message: "Validation failed",
      errors: format_changeset_errors(changeset)
    }
  end

  # Standard generic error string wrapper
  def error(%{error: message}) when is_binary(message) do
    %{status: "error", message: "An error occurred", errors: [message]}
  end

  def not_found do
    %{status: "error", message: "Resource lookup failed.", errors: ["Resource not found"]}
  end

  def unauthorized do
    %{
      status: "error",
      message: "Authentication failed.",
      errors: ["Invalid or missing authentication token"]
    }
  end

  def forbidden do
    %{status: "error", message: "Permission denied.", errors: ["Access denied"]}
  end

  # Custom controllers override message hooks
  def forbidden(%{message: message}),
    do: %{status: "error", message: "Permission denied", errors: [message]}

  def bad_request do
    %{status: "error", message: "Invalid request.", errors: ["Invalid request parameters"]}
  end

  def bad_request(%{message: message}),
    do: %{status: "error", message: "Invalid parameters", errors: [message]}

  def unprocessable_entity do
    %{
      status: "error",
      message: "Validation failed.",
      errors: ["The request contains invalid entity attributes"]
    }
  end

  def unprocessable_entity(%{message: message}),
    do: %{status: "error", message: "Validation failed", errors: [message]}

  def internal_server_error do
    %{
      status: "error",
      message: "Internal Server Error.",
      errors: ["An unexpected server-side error occurred"]
    }
  end

  # -----------------------------------------------------------
  # 3. Private Interpolation Serializer Helpers
  # -----------------------------------------------------------

  defp format_changeset_errors(%Changeset{} = changeset) do
    Changeset.traverse_errors(changeset, fn {message, opts} ->
      # Safely interpolates database rules like "should be at least %{count} characters"
      Regex.replace(~r"%{(\w+)}", message, fn _, key_str ->
        try do
          # Convert string token key to atom safely to locate parameter attributes
          key_atom = String.to_existing_atom(key_str)
          opts |> Keyword.get(key_atom, key_str) |> to_string()
        rescue
          ArgumentError -> key_str
        end
      end)
    end)
  end

  defp normalize_template(template) when is_atom(template), do: Atom.to_string(template)

  defp normalize_template(template) when is_binary(template),
    do: String.trim_trailing(template, ".json")
end
