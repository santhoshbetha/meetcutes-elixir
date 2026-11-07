defmodule Meetcutes.Workers.MailerWorker do
  use Meetcutes.Workers.WorkerHelper, queue: "mailer"

  @impl Oban.Worker
  def perform(%Job{
        args: %{"op" => "email", "encoded_email" => encoded_email, "config" => config}
      }) do
    email =
      encoded_email
      |> Base.decode64!()
      |> :erlang.binary_to_term()

    Meetcutes.Emails.Mailer.perform(:deliver_async, email, config)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(5)
end
