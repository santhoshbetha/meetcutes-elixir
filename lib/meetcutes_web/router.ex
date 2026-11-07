defmodule MeetcutesWeb.Router do
  use MeetcutesWeb, :router

  import MeetcutesWeb.UserAuth
  import Phoenix.LiveDashboard.Router

  pipeline :dashboard_auth do
    plug :accepts, ["html"]
    plug :dashboard_basic_auth
  end

  pipeline :api do
    plug :accepts, ["json"]
    # Automatically reads the Bearer token and assigns :current_user for all API requests
    plug :fetch_current_user
  end

  # Blocks logged-in users from accessing sign-up/login pages
  pipeline :api_unauthenticated do
    plug :redirect_if_user_is_authenticated
  end

  # Enforces an active session token before allowing access
  pipeline :api_authenticated do
    plug :require_authenticated_user
  end

  # Independent high-entropy gate for the MCP administrative command API.
  # This pipeline never reads a user bearer token.
  pipeline :mcp_admin do
    plug :accepts, ["json"]
    plug MeetcutesWeb.Plugs.McpAdminAuth
  end

  # Operator telemetry dashboard. Credentials are read at request time from
  # runtime configuration so no secrets are compiled into the release.
  scope "/" do
    pipe_through :dashboard_auth

    live_dashboard "/dashboard", metrics: MeetcutesWeb.Telemetry
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:meetcutes, :dev_routes) do
    scope "/dev" do
      pipe_through :api

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/api", MeetcutesWeb do
    pipe_through :api

    # Add this line right here
    get "/health", HealthController, :show
    delete "/users/logout", SessionController, :delete
    # Read-only reset-token validation for the React `/auth/confirm` page.
    # It lives outside `:api_unauthenticated` so a signed-in user can still
    # follow a recovery link, and it never consumes the token.
    get "/users/reset_password/:token", ResetPasswordController, :show

    # Native v1 credential-recovery API used by the React client.
    # These stay outside `:api_unauthenticated` as well so a signed-in user can
    # rotate a password or request a recovery link without being redirected.
    post "/v1/auth/forgot-password", ResetPasswordController, :create
    post "/v1/auth/reset-password", ResetPasswordController, :update
    post "/v1/auth/reset-password/:token", ResetPasswordController, :update
    get "/v1/auth/reset-password/:token", ResetPasswordController, :show

    # Email-change confirmation. Unauthenticated because the link is opened
    # from a mailbox; the single-use token is the credential.
    post "/users/confirm_email_change/:token", EmailChangeController, :confirm

    # Stripe signs the raw request body, so this route stays outside the
    # bearer-authenticated pipeline.
    post "/v1/payments/webhook", PaymentController, :webhook

    # Public, unauthenticated landing-page configuration.
    get "/v1/public/global-announcement", PublicController, :global_announcement
  end

  # MCP administrative command surface. Isolated from user authentication and
  # guarded only by the runtime X-MCP-Admin-Key shared secret.
  scope "/api", MeetcutesWeb do
    pipe_through :mcp_admin

    post "/v1/admin/mcp-action", AdminController, :mcp_action
  end

  scope "/api", MeetcutesWeb do
    pipe_through [:api, :api_unauthenticated]

    post "/users/register", RegistrationController, :create
    post "/users/login", SessionController, :create

    post "/users/reset_password", ResetPasswordController, :create
    put "/users/reset_password/:token", ResetPasswordController, :update

    post "/users/resend_confirmation", ConfirmationController, :resend
    post "/users/confirm/:token", ConfirmationController, :confirm
  end

  scope "/api", MeetcutesWeb do
    pipe_through [:api, :api_authenticated]

    put "/users/settings", SettingsController, :update
    put "/users/settings/profile", SettingsController, :update_profile
    put "/users/settings/user", SettingsController, :update_user
    put "/users/settings/timezone", SettingsController, :update_timezone
    delete "/users/settings", SettingsController, :delete
    get "/users/settings/confirm_email/:token", SettingsController, :confirm_email

    get "/users/settings/websocket_token", SettingsController, :websocket_token
    get "/users/settings/location_status", SettingsController, :location_status
    get "/users/profile", SettingsController, :profile

    get "/events", EventController, :index
    get "/events/joined_events", EventController, :joined_events
    get "/events/created_events", EventController, :created_events

    post "/events", EventController, :create
    post "/events/:id/join", EventController, :join
    post "/events/:id/leave", EventController, :leave
    post "/events/:id/cancel", EventController, :cancel

    put "/events/:id", EventController, :update
    delete "/events/cleanup/old", EventController, :delete_old_events

    get "/events/:id/download", EventController, :download

    post "/search/users", SearchController, :users
    get "/search/user/:identifier", SearchController, :user
    get "/search/user/id/:id", SearchController, :user_by_id

    post "/search/events", EventController, :search

    # Versioned search aliases used by external clients and security probes.
    get "/v1/search/users", SearchController, :users
    get "/v1/search/events", EventsController, :index

    post "/upload", UploadController, :upload
    post "/upload/avatar", UploadController, :upload_avatar
    get "/upload/images", UploadController, :list_images
    get "/upload/avatar", UploadController, :get_avatar

    # Users subscribe to meetcutes.us[token]
    get "/feeds/calendar/:user_token", UserCalendarController, :feed

    patch "/users/update_timezone", SettingsController, :update_timezone

    get "/events/:event_id/comments", DiscussionController, :index
    post "/events/:event_id/comments", DiscussionController, :create
    put "/comments/:id", DiscussionController, :update
    delete "/comments/:id", DiscussionController, :delete

    # Endpoints for your Anti-Cheat Questionnaire System
    get "/quiz/questions", QuestionController, :get_random_quiz_set
    post "/quiz/answers", QuestionController, :process_answer

    # Job status endpoint
    get "/jobs/:id", JobController, :status

    # Phase 2 profile / relationship API. These live under the authenticated
    # pipeline because every action needs the bearer user as the actor.
    get "/v1/profiles/me", ProfilesController, :me
    patch "/v1/profiles/me", ProfilesController, :update
    delete "/v1/profiles/me", ProfilesController, :deactivate
    get "/v1/users/check-handle", ProfilesController, :check_handle
    patch "/v1/users/me/set-handle", ProfilesController, :set_handle
    post "/v1/profiles/me/images", ProfilesController, :upload_image
    put "/v1/profiles/me/images", ProfilesController, :reorder_images
    delete "/v1/profiles/me/images/:slot", ProfilesController, :delete_image
    get "/v1/profiles/handle_available/:handle", ProfilesController, :handle_available
    get "/v1/profiles/:id", ProfilesController, :show

    get "/v1/relationships", RelationshipsController, :index
    get "/v1/relationships/blocked", RelationshipsController, :blocked
    get "/v1/relationships/muted", RelationshipsController, :muted
    get "/v1/relationships/liked", RelationshipsController, :liked
    get "/v1/relationships/liked-by", RelationshipsController, :liked_by
    post "/v1/relationships", RelationshipsController, :create
    delete "/v1/relationships/:kind/:target_id", RelationshipsController, :delete

    post "/v1/payments/create-checkout-session", PaymentController, :create_checkout_session
    post "/v1/payments/create-portal-session", PaymentController, :create_portal_session

    get "/v1/notifications", NotificationsController, :index
    patch "/v1/notifications/:id/read", NotificationsController, :read
    post "/v1/notifications/mark-all-read", NotificationsController, :mark_all_read

    get "/v1/locations/autocomplete", LocationsController, :autocomplete

    # Events slice. Every route is authenticated because create/join/leave act
    # as the bearer user, and list endpoints personalize attendance.
    get "/v1/events", EventsController, :index
    get "/v1/events/created", EventsController, :created
    get "/v1/events/joined", EventsController, :joined
    get "/v1/events/:event_id/check-fatigue", EventsController, :check_fatigue
    post "/v1/events", EventsController, :create
    get "/v1/events/:id", EventsController, :show
    post "/v1/events/:id/join", EventsController, :join
    delete "/v1/events/:id/join", EventsController, :leave
  end

  defp dashboard_basic_auth(conn, _opts) do
    auth = Application.get_env(:meetcutes, :dashboard_auth, [])
    username = Keyword.get(auth, :username)
    password = Keyword.get(auth, :password)

    if is_binary(username) and username != "" and is_binary(password) and password != "" do
      Plug.BasicAuth.basic_auth(conn, username: username, password: password)
    else
      conn
      |> Plug.Conn.send_resp(:service_unavailable, "Dashboard authentication is not configured")
      |> Plug.Conn.halt()
    end
  end
end
