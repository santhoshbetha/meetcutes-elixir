defmodule MeetcutesWeb.Presence do
  use Phoenix.Presence,
    otp_app: :meetcutes,
    pubsub_server: Meetcutes.PubSub
end
