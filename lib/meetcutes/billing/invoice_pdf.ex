defmodule Meetcutes.Billing.InvoicePDF do
  @moduledoc """
  Builds a lightweight PDF receipt with the pure-Elixir `pdf` package.
  """

  alias Meetcutes.Accounts.User
  alias Meetcutes.Billing.{Invoice, Receipt}

  def render(%Invoice{} = invoice, %User{} = user) do
    receipt = Receipt.render(invoice, user)

    Pdf.build([size: :a4, compress: true], fn pdf ->
      pdf
      |> Pdf.set_info(title: "MeetCutes Invoice #{invoice.id}")
      |> Pdf.set_font("Helvetica", 16)
      |> Pdf.text_at({50, 800}, "MeetCutes Premium Membership")
      |> Pdf.set_font("Helvetica", 10)
      |> write_lines(String.split(receipt, "\n"), 760)
      |> Pdf.export()
    end)
  end

  defp write_lines(pdf, [], _y), do: pdf

  defp write_lines(pdf, [line | rest], y) do
    pdf
    |> Pdf.text_at({50, y}, sanitize(line))
    |> write_lines(rest, y - 15)
  end

  defp sanitize(line) do
    line
    |> to_string()
    |> String.replace(~r/[^\x20-\x7E]/, "")
  end
end
