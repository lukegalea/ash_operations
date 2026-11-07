defmodule AshOperations.Webhook.Ingress do
  @moduledoc """
  One plug for every provider webhook, mounted at `POST /:provider`.

  Options: `providers:` (required, `%{"name" => module}` of
  `Operations.Webhook.Provider`s) and `telemetry_prefix:` (default
  `[:operations, :webhook]`).

  Order: resolve provider (404, body unread) -> cap by `content-length` (413)
  -> read raw bytes -> `verify` (401 / 503) -> decode (400) -> `dedup_key`
  (400) -> `enqueue`. Responses have empty bodies:

  | Status | When |
  |---|---|
  | 204 | enqueued, duplicate or ignored |
  | 400 | bad JSON, non-object, no dedup key, rejected payload |
  | 401 | bad or stale signature |
  | 404 | unknown provider |
  | 408 | body read timed out |
  | 413 | over the provider's cap |
  | 503 | no secret configured, insert failed, or the provider raised |

  The body is read here, not by `Plug.Parsers`, so the signature covers the
  exact bytes. Nothing is logged. One telemetry event per request carries the
  provider name, outcome and status, never an id, a header value or any body
  content.
  """

  @behaviour Plug

  @default_cap 65_536

  @impl true
  def init(opts) do
    %{
      providers: Keyword.fetch!(opts, :providers),
      telemetry_prefix: Keyword.get(opts, :telemetry_prefix, [:operations, :webhook])
    }
  end

  @impl true
  def call(conn, %{providers: providers} = opts) do
    started = System.monotonic_time()

    {conn, name, bytes, {status, outcome}, exception} =
      case Map.fetch(providers, conn.path_params["provider"]) do
        {:ok, mod} -> handle(conn, mod, provider_name(conn))
        :error -> {conn, :unknown, 0, {404, :unknown_provider}, nil}
      end

    metadata =
      %{provider: name, outcome: outcome, status: status}
      |> then(&if(exception, do: Map.put(&1, :exception, exception), else: &1))

    :telemetry.execute(
      opts.telemetry_prefix ++ [:received],
      %{bytes: bytes, duration: System.monotonic_time() - started},
      metadata
    )

    conn |> Plug.Conn.send_resp(status, "") |> Plug.Conn.halt()
  end

  defp provider_name(conn), do: conn.path_params["provider"]

  defp handle(conn, mod, name) do
    cap = cap(mod)

    if declared_length(conn) > cap do
      {conn, name, 0, {413, :too_large}, nil}
    else
      case read(conn, cap) do
        {:ok, raw, conn} when byte_size(raw) <= cap -> verified(conn, mod, name, raw)
        {:ok, raw, conn} -> {conn, name, byte_size(raw), {413, :too_large}, nil}
        {:more, _, conn} -> {conn, name, 0, {413, :too_large}, nil}
        {:error, :timeout} -> {conn, name, 0, {408, :timeout}, nil}
        {:error, _} -> {conn, name, 0, {400, :bad_request}, nil}
      end
    end
  end

  # Bandit raises (it does not return `{:error, :timeout}`) when a body read
  # times out or the peer drops; map those to a status so telemetry still fires.
  defp read(conn, cap) do
    Plug.Conn.read_body(conn, length: cap, read_length: cap, read_timeout: 15_000)
  rescue
    e -> if Plug.Exception.status(e) == 408, do: {:error, :timeout}, else: {:error, :read_failed}
  end

  defp cap(mod) do
    Code.ensure_loaded(mod)
    if function_exported?(mod, :max_body_bytes, 0), do: mod.max_body_bytes(), else: @default_cap
  end

  defp declared_length(conn) do
    with [value] <- Plug.Conn.get_req_header(conn, "content-length"),
         {n, ""} <- Integer.parse(value) do
      n
    else
      _ -> 0
    end
  end

  defp verified(conn, mod, name, raw) do
    bytes = byte_size(raw)

    result =
      try do
        process(conn, mod, raw)
      rescue
        e -> {:crashed, e.__struct__}
      end

    case result do
      {:crashed, module} -> {conn, name, bytes, {503, :crashed}, module}
      {status, outcome} -> {conn, name, bytes, {status, outcome}, nil}
    end
  end

  defp process(conn, mod, raw) do
    with :ok <- verify(mod, conn, raw),
         {:ok, payload} <- decode(raw),
         {:ok, key} <- dedup(mod, conn, payload) do
      case mod.enqueue(payload, key) do
        {:ok, outcome} when outcome in [:enqueued, :duplicate, :ignored] -> {204, outcome}
        {:reject, _} -> {400, :rejected}
        {:error, _} -> {503, :unavailable}
      end
    end
  end

  defp verify(mod, conn, raw) do
    case mod.verify(conn, raw) do
      :ok -> :ok
      {:error, :not_configured} -> {503, :not_configured}
      {:error, _} -> {401, :unauthorized}
    end
  end

  defp decode(raw) do
    case Jason.decode(raw, floats: :decimals) do
      {:ok, %{} = payload} -> {:ok, payload}
      _ -> {400, :bad_json}
    end
  end

  defp dedup(mod, conn, payload) do
    case mod.dedup_key(conn, payload) do
      {:ok, key} -> {:ok, key}
      {:error, _} -> {400, :bad_request}
    end
  end
end
