defmodule AshOperations.Error do
  @moduledoc """
  A typed failure from a declared operation. Callers branch on `reason`:

  | `reason` | Meaning | Caller's move |
  |---|---|---|
  | `:unauthorized` | 401 | fix the credential (operations, not code) |
  | `:forbidden` | 403 | stop; the key lacks the permission |
  | `:payment_required` | 402 | stop; billing or credits |
  | `:not_found` | 404 | per caller: a delete of a missing id is done |
  | `:conflict` | 409 | per caller |
  | `:gone` | 410 | per caller |
  | `:unprocessable` | 422 | a bug in the declaration or the arguments |
  | `:bad_request` | 400, or arguments that cannot build a request | as above |
  | `:rate_limited` | 429 after retries | snooze for `retry_after_ms` |
  | `:server_error` | 5xx after retries, on an idempotent operation | retry later |
  | `:timeout` | no response in time, on an idempotent operation, after retries | retry later |
  | `:transport` | the request was never answered (DNS, refused, closed) after retries | retry later |
  | `:ambiguous` | a non-idempotent call timed out or got a 5xx: it may have happened | reconcile, never re-send |
  | `:disclosure_refused` | the host's disclosure gate refused; nothing was sent | `provider_code` says why |
  | `:not_configured` | the transport has no credential or base URL | operations, not code |

  Fields carry **no response body and no credential**: `status`,
  `provider_code` (an error *code*, never a message), `request_id` (the
  provider's id for support), `retry_after_ms`.
  """

  use Splode.Error,
    fields: [
      :reason,
      :provider,
      :operation,
      :status,
      :provider_code,
      :request_id,
      :retry_after_ms
    ],
    class: :unknown

  @type t :: %__MODULE__{}

  @type reason ::
          :unauthorized
          | :forbidden
          | :payment_required
          | :not_found
          | :conflict
          | :gone
          | :unprocessable
          | :bad_request
          | :rate_limited
          | :server_error
          | :timeout
          | :transport
          | :ambiguous
          | :disclosure_refused
          | :not_configured

  @impl true
  def message(%__MODULE__{} = error) do
    [
      "provider operation: #{error.reason}",
      error.provider && "provider=#{error.provider}",
      error.operation && "operation=#{error.operation}",
      error.status && "status=#{error.status}",
      error.provider_code && "code=#{error.provider_code}",
      error.request_id && "request_id=#{error.request_id}",
      error.retry_after_ms && "retry_after_ms=#{error.retry_after_ms}"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join(" ")
  end

  @doc "The `Error` inside whatever an action returned, or nil."
  def unwrap(%__MODULE__{} = error), do: error
  def unwrap(%{errors: errors}) when is_list(errors), do: Enum.find_value(errors, &unwrap/1)
  def unwrap(%{error: error}), do: unwrap(error)
  def unwrap(_), do: nil

  @doc "The typed reason inside an action's error, or nil."
  def reason(error) do
    case unwrap(error) do
      %__MODULE__{reason: reason} -> reason
      nil -> nil
    end
  end
end
