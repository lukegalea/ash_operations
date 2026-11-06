defmodule AshOperations.Test.WebhookProvider do
  @moduledoc """
  A synthetic webhook provider. The payload's `"mode"` picks `enqueue/2`'s
  answer; the `x-test-verify` header picks `verify/2`'s. It reports to the
  calling process.
  """
  @behaviour AshOperations.Webhook.Provider

  @impl true
  def max_body_bytes, do: 1_024

  @impl true
  def verify(conn, raw) do
    send(self(), {:verified, raw})

    case Plug.Conn.get_req_header(conn, "x-test-verify") do
      ["unauthorized"] -> {:error, :unauthorized}
      ["not_configured"] -> {:error, :not_configured}
      _ -> :ok
    end
  end

  @impl true
  def dedup_key(conn, _payload) do
    case Plug.Conn.get_req_header(conn, "x-test-key") do
      ["none"] -> {:error, :bad_request}
      _ -> {:ok, "key-1"}
    end
  end

  @impl true
  def enqueue(payload, key) do
    send(self(), {:enqueued, payload, key})

    case payload["mode"] do
      "duplicate" -> {:ok, :duplicate}
      "ignored" -> {:ok, :ignored}
      "reject" -> {:reject, :nope}
      "error" -> {:error, :down}
      "raise" -> raise "marker-secret-in-message"
      _ -> {:ok, :enqueued}
    end
  end
end

defmodule AshOperations.Test.DefaultCapProvider do
  @moduledoc false
  @behaviour AshOperations.Webhook.Provider
  @impl true
  def verify(_conn, _raw), do: :ok
  @impl true
  def dedup_key(_conn, _payload), do: {:ok, "k"}
  @impl true
  def enqueue(_payload, _key), do: {:ok, :enqueued}
end
