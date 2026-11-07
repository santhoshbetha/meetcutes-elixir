defmodule MeetcutesWeb.UploadController do
  use MeetcutesWeb, :controller

  alias Meetcutes.Accounts.User
  alias Meetcutes.ImageUploader
  alias Meetcutes.Repo
  alias Meetcutes.Uploads
  alias MeetcutesWeb.UploadJSON

  action_fallback MeetcutesWeb.FallbackController

  # POST "/upload"
  #
  # Uploads are written straight from the multipart request to R2/S3. There is
  # no temp copy and no background job carrying a local path, so a container
  # restart can never leave an orphaned or missing upload.
  def upload(conn, %{"file" => %Plug.Upload{} = upload}) do
    user = conn.assigns.current_user

    case Uploads.store(user, :image, upload) do
      {:ok, media} ->
        conn
        |> put_status(:created)
        |> json(UploadJSON.image(%{media: media}))

      {:error, reason} ->
        {:error, reason}
    end
  end

  def upload(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(UploadJSON.error(%{error: "No file provided"}))
  end

  # POST "/upload/avatar"
  def upload_avatar(conn, %{"file" => %Plug.Upload{} = upload}) do
    user = conn.assigns.current_user

    with {:ok, media} <- Uploads.store(user, :avatar, upload),
         {:ok, _updated_user} <- persist_avatar(user, media) do
      conn
      |> put_status(:ok)
      |> json(UploadJSON.avatar(%{avatar_url: media.url, media: media}))
    end
  end

  def upload_avatar(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(UploadJSON.error(%{error: "No file provided"}))
  end

  # GET "/upload/images"
  def list_images(conn, _params) do
    user = conn.assigns.current_user
    images = ImageUploader.list_user_images(user)

    conn
    |> put_status(:ok)
    |> json(UploadJSON.images(%{images: images}))
  end

  # GET "/upload/avatar"
  def get_avatar(conn, _params) do
    user = conn.assigns.current_user

    case ImageUploader.get_user_avatar(user) do
      {:ok, avatar_url} ->
        conn
        |> put_status(:ok)
        |> json(UploadJSON.avatar(%{avatar_url: avatar_url}))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(UploadJSON.error(%{error: "Avatar not found"}))
    end
  end

  defp persist_avatar(%User{} = user, media) do
    user
    |> User.media_changeset(%{avatar: media})
    |> Repo.update()
  end
end
