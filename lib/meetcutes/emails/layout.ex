defmodule Meetcutes.Emails.Layout do
  @moduledoc """
  Shared, inline-styled HTML layout for transactional email.

  Email clients strip external stylesheets and many modern CSS features, so the
  layout uses table-based structure and inline styles. The palette mirrors the
  smoothed light-mode branding: warm stone background, white card, subtle amber
  border, and the orange/red/pink accent gradient.
  """

  import Plug.HTML, only: [html_escape: 1]

  @from_name "Meetcutes"
  @default_from_email "noreply@meetcutes.us"

  @doc """
  Returns the configured white-labeled sender as a Swoosh recipient tuple.
  """
  def from, do: {@from_name, from_email()}

  @doc """
  Returns the globally configured transactional sender address.
  """
  def from_email do
    :meetcutes
    |> Application.get_env(:from_email, @default_from_email)
    |> normalize_email()
  end

  @doc """
  Builds a client URL on the verified static frontend domain.

  The caller may pass either a path (`/changepassword`) or a full URL; paths
  are joined to the configured `Meetcutes.Accounts` frontend origin so emails
  never deep-link into the internal API host.
  """
  def frontend_url(path \\ "/") do
    base = Meetcutes.Accounts.frontend_url()

    cond do
      path in [nil, "", "/"] -> base <> "/"
      String.starts_with?(path, "/") -> base <> path
      true -> base <> "/" <> path
    end
  end

  @doc """
  Normalises an absolute or relative link against the frontend origin.
  """
  def ensure_absolute_url(url) when is_binary(url) do
    cond do
      String.starts_with?(url, ["https://", "http://"]) -> url
      String.starts_with?(url, "/") -> frontend_url(url)
      true -> url
    end
  end

  def ensure_absolute_url(_url), do: frontend_url("/")

  @doc """
  Wraps inner HTML in the branded transactional email shell.
  """
  def document(title, preview, inner_html) do
    """
    <!DOCTYPE html>
    <html lang="en" style="color-scheme: light only;">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta name="color-scheme" content="light only">
      <meta name="supported-color-schemes" content="light only">
      <title>#{html_escape(title)}</title>
    </head>
    <body style="margin:0; padding:0; background-color:#fafaf9; color:#1c1917; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
      <div style="display:none; max-height:0; overflow:hidden; opacity:0; color:transparent;">
        #{html_escape(preview)}
      </div>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#fafaf9;">
        <tr>
          <td align="center" style="padding:40px 16px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px; background-color:#ffffff; border:1px solid #f1e7dc; border-radius:20px; overflow:hidden;">
              <tr>
                <td style="padding:0; background-color:#f97316; background-image:linear-gradient(135deg,#f97316 0%,#ef4444 52%,#ec4899 100%);">
                  <div style="padding:28px 36px;">
                    <div style="font-size:22px; line-height:28px; font-weight:800; letter-spacing:-0.02em; color:#ffffff;">
                      Meetcutes
                    </div>
                    <div style="margin-top:6px; font-size:13px; line-height:20px; color:rgba(255,255,255,0.86);">
                      Real people. Real connection.
                    </div>
                  </div>
                </td>
              </tr>
              <tr>
                <td style="padding:36px 36px 24px 36px;">
                  <h1 style="margin:0 0 20px 0; font-size:26px; line-height:34px; font-weight:800; letter-spacing:-0.03em; color:#1c1917;">
                    #{html_escape(title)}
                  </h1>
                  #{inner_html}
                </td>
              </tr>
              <tr>
                <td style="padding:0 36px 36px 36px;">
                  <div style="padding-top:22px; border-top:1px solid #f1e7dc; font-size:12px; line-height:20px; color:#78716c;">
                    You are receiving this transactional email because of activity on your Meetcutes account.
                    <br>
                    Meetcutes &middot; <a href="#{html_escape(frontend_url("/"))}" style="color:#b45309; text-decoration:none;">meetcutes.us</a>
                  </div>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  @doc """
  Renders a paragraph with escaped text.
  """
  def paragraph(text) do
    ~s(<p style="margin:0 0 16px 0; font-size:16px; line-height:26px; color:#44403c;">#{html_escape(text)}</p>)
  end

  @doc """
  Renders a paragraph with a single inline link.
  """
  def paragraph_with_link(prefix, url, label, suffix \\ "") do
    ~s(<p style="margin:0 0 16px 0; font-size:16px; line-height:26px; color:#44403c;">#{html_escape(prefix)}<a href="#{html_escape(url)}" style="color:#c2410c; font-weight:600; text-decoration:underline;">#{html_escape(label)}</a>#{html_escape(suffix)}</p>)
  end

  @doc """
  Renders the primary call-to-action button with a copyable fallback link.
  """
  def button(label, url) do
    """
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:26px 0 24px 0;">
      <tr>
        <td align="center" style="border-radius:12px; background-color:#f97316; background-image:linear-gradient(135deg,#f97316 0%,#ef4444 52%,#ec4899 100%);">
          <a href="#{html_escape(url)}" style="display:inline-block; padding:14px 28px; font-size:15px; line-height:20px; font-weight:700; color:#ffffff; text-decoration:none; border-radius:12px;">#{html_escape(label)}</a>
        </td>
      </tr>
    </table>
    <p style="margin:0 0 16px 0; font-size:12px; line-height:20px; color:#78716c; word-break:break-all;">
      If the button does not work, copy and paste this link into your browser:<br>
      <a href="#{html_escape(url)}" style="color:#b45309; text-decoration:underline;">#{html_escape(url)}</a>
    </p>
    """
  end

  @doc """
  Renders low-emphasis supporting copy.
  """
  def muted(text) do
    ~s(<p style="margin:0; font-size:13px; line-height:22px; color:#78716c;">#{html_escape(text)}</p>)
  end

  defp normalize_email(value) when is_binary(value) do
    case String.trim(value) do
      "" -> @default_from_email
      trimmed -> trimmed
    end
  end

  defp normalize_email(_value), do: @default_from_email
end
