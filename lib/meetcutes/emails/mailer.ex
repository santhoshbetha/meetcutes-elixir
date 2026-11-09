# Meetcutes: A lightweight social networking server
# Copyright Ac 2025 Meetcutes Authors <https://meetcutes.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Meetcutes.Emails.Mailer do
  @moduledoc """
  Queue-facing transactional mailer.

  Templates call `deliver_async/2`, which serialises the email into an Oban
  `MailerWorker` job so a controller never waits on Resend. The worker calls
  `perform/3`, which hands the email to `Meetcutes.Mailer` for actual delivery.

  `Meetcutes.Mailer` is the single source of truth for the production adapter
  (Resend) and API client (Finch), so this module never duplicates secrets or
  provider configuration.
  """

  alias Meetcutes.Workers.MailerWorker
  alias Swoosh.DeliveryError

  @spec enabled?() :: boolean()
  def enabled?, do: Meetcutes.Config.get([__MODULE__, :enabled])

  @doc """
  Serialises an email and adds it to the Oban mailer queue.
  """
  def deliver_async(email, config \\ []) do
    encoded_email =
      email
      |> :erlang.term_to_binary()
      |> Base.encode64()

    MailerWorker.enqueue("email", %{"encoded_email" => encoded_email, "config" => config})
  end

  @doc """
  Oban callback for an `"email"` job.
  """
  def perform(:deliver_async, email, config), do: deliver(email, config)

  @doc """
  Delivers an email through the configured Swoosh adapter.
  """
  @spec deliver(Swoosh.Email.t(), Keyword.t()) :: {:ok, term} | {:error, term}
  def deliver(email, config \\ [])

  def deliver(email, config) do
    case enabled?() do
      true -> Meetcutes.Mailer.deliver(email, config)
      false -> {:error, :deliveries_disabled}
    end
  end

  @spec deliver!(Swoosh.Email.t(), Keyword.t()) :: term | no_return
  def deliver!(email, config \\ [])

  def deliver!(email, config) do
    case deliver(email, config) do
      {:ok, result} -> result
      {:error, reason} -> raise DeliveryError, reason: reason
    end
  end
end
