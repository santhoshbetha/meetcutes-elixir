defmodule Meetcutes.Billing do
  @moduledoc """
  Premium membership billing.

  Checkout is a one-time $50 Stripe Checkout purchase that grants a 365-day
  membership. Stripe webhooks are the source of truth; every completed session
  produces an invoice, an archived PDF receipt, an email, and a subscription
  expiry update.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Meetcutes.Accounts.User
  alias Meetcutes.Billing.{Invoice, InvoicePDF, InvoiceStorage, Receipt, StripeClient}
  alias Meetcutes.Mailer
  alias Meetcutes.Repo

  @amount_cents 5_000
  @membership_days 365

  @doc """
  Resolves the membership price in cents for a user.

  `accepted_onetime_fees_amount` records the fee agreed at signup, in whole
  dollars. Admins may raise the current price later without repricing existing
  members, so each checkout honors the user's stored accepted amount. Legacy or
  unset values fall back to the $50 launch price.
  """
  def amount_cents_for(%User{accepted_onetime_fees_amount: amount})
      when is_integer(amount) and amount > 0 do
    amount * 100
  end

  def amount_cents_for(_user), do: amount_cents()

  @doc "The current public annual membership price in cents."
  def amount_cents do
    :meetcutes
    |> Application.get_env(:membership_fee_usd, 50)
    |> case do
      fee when is_integer(fee) and fee > 0 -> fee * 100
      _ -> @amount_cents
    end
  end

  @doc "The membership length in days."
  def membership_days, do: @membership_days

  @doc """
  True when the user has a non-expired annual membership.
  """
  def subscription_active?(%User{subscription_expires_at: nil}), do: false

  def subscription_active?(%User{subscription_expires_at: %DateTime{} = expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  def subscription_active?(_user), do: false

  @doc """
  Creates a hosted Stripe Checkout session for the signed-in user.

  Returns `{:ok, %{id: session_id, url: checkout_url}}`.
  """
  def create_checkout_session(%User{} = user) do
    amount_cents = amount_cents_for(user)

    # IO.inspect(amount_cents)

    params = %{
      mode: "payment",
      success_url: success_url(),
      cancel_url: cancel_url(),
      client_reference_id: user.id,
      customer_email: user.email,
      metadata: %{
        user_id: user.id,
        product: "premium_annual",
        accepted_amount_cents: amount_cents
      },
      line_items: [line_item(amount_cents)]
    }

    # IO.inspect(params)

    stripe_client().create_checkout_session(params)
  end

  @doc """
  Creates a Stripe Billing Portal session for a user with a linked customer id.

  Returns a graceful `{:error, :missing_stripe_customer}` when the account has
  not completed a Stripe checkout yet.
  """
  def create_portal_session(%User{stripe_customer_id: customer_id})
      when is_binary(customer_id) and customer_id != "" do
    stripe_client().create_portal_session(%{
      customer: customer_id,
      return_url: portal_return_url()
    })
  end

  def create_portal_session(_user), do: {:error, :missing_stripe_customer}

  @doc """
  Verifies a Stripe webhook and fulfills `checkout.session.completed`.

  Unknown event types are ignored so Stripe retries do not fail.
  """
  def handle_webhook(payload, signature) when is_binary(payload) do
    with {:ok, event} <- stripe_client().construct_event(payload, signature) do
      handle_event(event)
    end
  end

  def handle_event(%{"type" => "checkout.session.completed", "data" => %{"object" => session}}) do
    process_checkout_completed(session)
  end

  def handle_event(_event), do: {:ok, :ignored}

  @doc """
  Processes a completed checkout session map.

  Exposed for tests and for future admin replays; production goes through
  `handle_webhook/2`.
  """
  def process_checkout_completed(session) when is_map(session) do
    user_id = get_in(session, ["metadata", "user_id"]) || session["client_reference_id"]
    charge_id = session["payment_intent"] || session["id"]

    with {:ok, user} <- fetch_user(user_id),
         amount = normalize_amount(session["amount_total"], amount_cents_for(user)),
         {:ok, invoice} <- fulfill_invoice(user, charge_id, amount, session["customer"]) do
      finalize_invoice(invoice, user)
    end
  end

  def process_checkout_completed(_session), do: {:error, :invalid_session}

  defp fulfill_invoice(_user, nil, _amount, _customer), do: {:error, :missing_charge_id}

  defp fulfill_invoice(%User{} = user, charge_id, amount, customer) do
    case Repo.get_by(Invoice, stripe_charge_id: charge_id) do
      %Invoice{} = invoice ->
        {:ok, maybe_extend_subscription(user, invoice.period_end)}

        {:ok, invoice}

      nil ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        period_end = DateTime.add(now, @membership_days, :day)

        Repo.transaction(fn ->
          invoice =
            %Invoice{}
            |> Invoice.changeset(%{
              stripe_charge_id: charge_id,
              amount: amount,
              period_start: now,
              period_end: period_end
            })
            |> Ecto.Changeset.put_change(:user_id, user.id)
            |> Repo.insert!()

          user
          |> Ecto.Changeset.change(%{
            subscription_expires_at: period_end,
            stripe_customer_id: customer || user.stripe_customer_id
          })
          |> Repo.update!()

          invoice
        end)
    end
  end

  defp maybe_extend_subscription(%User{} = user, %DateTime{} = period_end) do
    current = user.subscription_expires_at

    if is_nil(current) or DateTime.compare(current, period_end) == :lt do
      user
      |> Ecto.Changeset.change(%{subscription_expires_at: period_end})
      |> Repo.update()
    else
      {:ok, user}
    end
  end

  defp maybe_extend_subscription(user, _period_end), do: {:ok, user}

  defp finalize_invoice(%Invoice{receipt_key: key} = invoice, %User{})
       when is_binary(key) and key != "" do
    {:ok, invoice}
  end

  defp finalize_invoice(%Invoice{} = invoice, %User{} = user) do
    receipt = Receipt.render(invoice, user)

    with {:ok, pdf} <- render_pdf(invoice, user),
         {:ok, stored} <- store_receipt(user, invoice, pdf) do
      invoice =
        invoice
        |> Ecto.Changeset.change(%{
          receipt_key: stored.key,
          receipt_url: stored.url
        })
        |> Repo.update!()

      deliver_receipt(user, invoice, receipt)
      {:ok, invoice}
    else
      error ->
        Logger.warning("Invoice #{invoice.id} fulfilled without a stored PDF: #{inspect(error)}")
        deliver_receipt(user, invoice, receipt)
        {:ok, invoice}
    end
  end

  defp render_pdf(invoice, user) do
    {:ok, InvoicePDF.render(invoice, user)}
  rescue
    error -> {:error, {:pdf_failed, Exception.message(error)}}
  end

  defp store_receipt(user, invoice, pdf) do
    filename = "invoice_#{invoice.id}.pdf"

    case InvoiceStorage.store(user, filename, pdf, "application/pdf") do
      {:ok, stored} -> {:ok, stored}
      {:error, reason} -> {:error, {:storage_failed, reason}}
    end
  end

  defp deliver_receipt(user, invoice, receipt) do
    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(user.email)
      |> Swoosh.Email.from({"Meetcutes", "hello@meetcutes.us"})
      |> Swoosh.Email.subject("Your MeetCutes premium membership receipt (##{invoice.id})")
      |> Swoosh.Email.text_body(receipt)

    # Meetcutes.Mailer owns the runtime Resend adapter in production.
    case Mailer.deliver(email) do
      {:ok, _result} -> :ok
      {:error, reason} -> Logger.warning("Invoice email failed: #{inspect(reason)}")
    end
  end

  defp fetch_user(user_id) when is_binary(user_id) do
    case Repo.get(User, user_id) do
      %User{deleted_at: nil} = user -> {:ok, user}
      _ -> {:error, :user_not_found}
    end
  end

  defp fetch_user(_user_id), do: {:error, :user_not_found}

  defp normalize_amount(amount, _fallback) when is_integer(amount) and amount > 0, do: amount

  defp normalize_amount(amount, fallback) when is_binary(amount) do
    case Integer.parse(amount) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp normalize_amount(_amount, fallback), do: fallback

  defp line_item(amount_cents) do
    # Dynamic price data keeps the checkout aligned with the amount this user
    # accepted at signup, even if the public price changes later.
    %{
      price_data: %{
        currency: "usd",
        unit_amount: amount_cents,
        product_data: %{name: "MeetCutes Premium Membership (1 year)"}
      },
      quantity: 1
    }
  end

  defp success_url do
    stripe_config(:success_url) || "#{frontend_url()}/dashboard?payment=success"
  end

  defp cancel_url do
    stripe_config(:cancel_url) || "#{frontend_url()}/dashboard?payment=cancelled"
  end

  defp portal_return_url do
    stripe_config(:portal_return_url) || "#{frontend_url()}/dashboard?tab=settings"
  end

  defp frontend_url do
    stripe_config(:frontend_url) ||
      Meetcutes.Accounts.frontend_url()
  end

  defp stripe_config(key) do
    :meetcutes
    |> Application.get_env(:stripe, [])
    |> Keyword.get(key)
  end

  defp stripe_client do
    Application.get_env(:meetcutes, :stripe_client, StripeClient.Live)
  end
end
