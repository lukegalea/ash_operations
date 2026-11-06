defmodule AshOperations.Retry do
  @moduledoc """
  The one retry table every transport shares.

  | Outcome | Idempotent operation | Non-idempotent operation |
  |---|---|---|
  | 429 | retry after `Retry-After` (or backoff) | same: the provider refused it, nothing happened |
  | 5xx | retry | `:ambiguous`, never re-sent |
  | timeout | retry, then `:timeout` | `:ambiguous`, never re-sent |
  | not sent (DNS, refused, unreachable) | retry | retry: provably never reached the provider |
  | other transport failure | retry | `:ambiguous` |
  | other 4xx | fail | fail |

  A wait longer than `max_delay_ms` is not slept: the call fails with
  `retry_after_ms` set so a job can snooze instead of holding a worker.
  """

  @not_sent [:econnrefused, :nxdomain, :ehostunreach, :enetunreach, :eaddrnotavail]

  @type outcome ::
          {:status, pos_integer(), reason :: atom()}
          | {:timeout}
          | {:transport, reason :: term()}

  @type decision :: {:retry, delay_ms :: non_neg_integer()} | {:fail, reason :: atom()}

  @doc """
  Decide what to do after attempt `n` (1-based).

  `opts`: `:idempotent?`, `:retry_after_ms` (nil when absent),
  `:max_attempts`, `:max_delay_ms`, `:base_backoff_ms`.
  """
  @spec decide(outcome(), pos_integer(), keyword()) :: decision()
  def decide(outcome, n, opts) do
    idempotent? = Keyword.fetch!(opts, :idempotent?)

    case classify(outcome, idempotent?) do
      {:retryable, reason} -> maybe_retry(reason, n, opts)
      {:final, reason} -> {:fail, reason}
    end
  end

  defp classify({:status, 429, _}, _idem), do: {:retryable, :rate_limited}
  defp classify({:status, s, _}, true) when s >= 500, do: {:retryable, :server_error}
  defp classify({:status, s, _}, false) when s >= 500, do: {:final, :ambiguous}
  defp classify({:status, _s, reason}, _idem), do: {:final, reason}
  defp classify({:timeout}, true), do: {:retryable, :timeout}
  defp classify({:timeout}, false), do: {:final, :ambiguous}
  defp classify({:transport, r}, _idem) when r in @not_sent, do: {:retryable, :transport}
  defp classify({:transport, _r}, true), do: {:retryable, :transport}
  defp classify({:transport, _r}, false), do: {:final, :ambiguous}

  defp maybe_retry(reason, n, opts) do
    delay = Keyword.get(opts, :retry_after_ms) || backoff(n, opts)

    if n < Keyword.get(opts, :max_attempts, 3) and
         delay <= Keyword.get(opts, :max_delay_ms, 10_000) do
      {:retry, delay}
    else
      {:fail, reason}
    end
  end

  defp backoff(n, opts), do: Keyword.get(opts, :base_backoff_ms, 500) * Integer.pow(2, n - 1)

  @doc false
  def not_sent_reasons, do: @not_sent
end
