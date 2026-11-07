defmodule MeetcutesWeb.UserAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias Meetcutes.Accounts

  @doc """
  API Plug: Reads the bearer token and assigns the raw user directly to the connection assigns.
  """
  def fetch_current_user(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {user, _token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      Accounts.touch_last_seen(user)
      Logger.metadata(user_id: user.id)
      assign(conn, :current_user, user)
    else
      _any ->
        assign(conn, :current_user, nil)
    end
  end

  @doc """
  API Plug: Enforces authentication by checking if a raw user exists in assigns.
  Returns a clean 401 Unauthorized JSON payload instead of a redirect.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{status: "error", message: "You must log in to access this resource."})
      |> halt()
    end
  end

  @doc """
  API Plug: Blocks logged-in users from accessing sign-up/login pages.
  Returns a clean 403 Forbidden payload if an active session tries to re-authenticate.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You are already logged in."})
      |> halt()
    else
      conn
    end
  end

  @doc """
  API Plug: Restricts highly sensitive endpoints unless the user has inputted their
  password very recently.
  """
  def require_sudo_mode(conn, _opts) do
    if conn.assigns[:current_user] && Accounts.sudo_mode?(conn.assigns.current_user, -10) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "You must re-authenticate to access this resource."})
      |> halt()
    end
  end
end
