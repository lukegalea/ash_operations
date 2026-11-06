defmodule AshOperations.Test.Transport do
  @moduledoc """
  The synthetic provider's transport. Answers come from a `Req.Test` stub named
  after this module, so every test owns its own stub and can run async.
  Waits are reported to the calling process as `{:slept, ms}` instead of slept.
  """
  use AshOperations.Http

  @impl true
  def config do
    if Process.get(:operations_test_unconfigured) do
      {:error, :not_configured}
    else
      test_pid = self()

      {:ok,
       %{
         base_url: "http://widgets.test",
         auth: {:bearer, "synthetic-test-token"},
         headers: [{"x-widgets-version", "2026-01-01"}],
         req_options: [plug: {Req.Test, __MODULE__}],
         sleep: fn ms -> send(test_pid, {:slept, ms}) end,
         base_backoff_ms: 1,
         max_delay_ms: 5_000
       }}
    end
  end

  # The provider's error envelope: `{"code": "NOT_FOUND", "requestId": "...", "message": "..."}`.
  # Codes and ids only; the message is never read.
  @impl true
  def classify(%{body: %{"code" => code} = body} = response) when is_binary(code) do
    %{
      reason: AshOperations.Http.status_reason(response.status),
      provider_code: code,
      request_id: body["requestId"]
    }
  end

  def classify(response), do: AshOperations.Http.by_status(response)
end
