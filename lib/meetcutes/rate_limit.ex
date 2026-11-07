defmodule Meetcutes.RateLimit do
  @moduledoc """
  ETS-backed token-bucket limiter used by the search API.

  A bucket holds 60 tokens; each search costs 6 tokens, so a caller can burst
  ten searches and then refills at one token per second (ten searches per
  minute steady-state).
  """

  use Hammer, backend: :ets, algorithm: :token_bucket
end
