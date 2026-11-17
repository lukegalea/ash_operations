defmodule AshOperations.Http do
  @moduledoc """
  The shared `Req` transport. A provider's transport is a module that `use`s
  this one and supplies its configuration and, optionally, its own error
  classification:

      defmodule MyApp.Provider.Proxy do
        use AshOperations.Http

        @impl true
        def config do
          case System.get_env("ACME_API_KEY") do
            key when key in [nil, ""] -> {:error, :not_configured}
            key -> {:ok, %{base_url: "https://api.acme.example", auth: {:bearer, key}}}
          end
        end
      end

  `config/0` is read on every call (secrets are runtime, never compile-time)
  and returns:

    * `:base_url` (required) and `:auth` (`{:bearer, token}` or nil);
    * `:headers` — extra headers on every request (e.g. an API version pin);
    * `:redirect` — whether a 3xx is followed (default `true`). A transport that
      sends to an address it vetted itself sets `false`: a followed redirect would
      reach an address nobody vetted, with the same body. An unfollowed 3xx fails
      with reason `:bad_request` and its `status`;
    * `:req_options` — merged last; tests pass `plug: {Req.Test, Module}`;
    * `:max_attempts` (3), `:max_delay_ms` (10_000), `:base_backoff_ms` (500),
      `:sleep` (a 1-arity fun; default `Process.sleep/1`).

  ## Per-call configuration

  A transport whose destination or credential depends on the call implements
  `config/1` instead of `config/0`. It receives the operation's metadata, whose
  `call` holds the action's actor, tenant and `in: :context` params
  (`AshOperations.Transport`):

      @impl true
      def config(%{call: %{tenant: tenant, context_params: %{endpoint_id: id}}}) do
        with {:ok, endpoint} <- MyApp.Webhooks.endpoint(tenant, id) do
          {:ok, %{base_url: endpoint.url, redirect: false, secret: endpoint.secret}}
        end
      end

  When both are defined, `config/1` is used. The map may carry keys of the
  transport's own (`:secret` above); only `sign/3` reads them.

  ## Signing

  A transport that signs requests implements `sign/3`. It receives the exact body
  bytes that will be sent (`""` without a body), the metadata and the config, and
  returns extra headers. A JSON body is encoded here, once, so the signature covers
  the bytes on the wire. A multipart body is encoded by `Req`, so `sign/3` receives
  `nil` for one. It is called once per call, and its headers go on every attempt.

  This module holds the only `Req` call on the operations path. Retrying
  follows `AshOperations.Retry`. JSON is decoded with
  floats as `Decimal`.

  ## Telemetry

  `telemetry_prefix ++ [:start | :stop | :exception]`, with structural metadata
  only: provider, operation, method, effect, attempts, status, reason. No path
  (it carries ids), no query, no body, no header.
  """

  alias AshOperations.{Error, Retry, Transport}

  @type config :: %{
          required(:base_url) => String.t(),
          optional(:auth) => {:bearer, String.t()} | nil,
          optional(:headers) => [{String.t(), String.t()}],
          optional(:redirect) => boolean(),
          optional(:req_options) => keyword(),
          optional(:max_attempts) => pos_integer(),
          optional(:max_delay_ms) => non_neg_integer(),
          optional(:base_backoff_ms) => non_neg_integer(),
          optional(:sleep) => (non_neg_integer() -> any()),
          optional(atom()) => term()
        }

  @type fields :: %{
          required(:reason) => Error.reason(),
          optional(:provider_code) => String.t() | nil,
          optional(:request_id) => String.t() | nil
        }

  @doc "The provider's runtime configuration, or `{:error, :not_configured}`."
  @callback config() :: {:ok, config()} | {:error, :not_configured}

  @doc """
  The configuration for one call, from its metadata (`meta.call` holds the actor,
  the tenant and the `in: :context` params). Used instead of `config/0` when
  defined. An error fails the call before anything is sent: `{:error, reason}`, or
  `{:error, {reason, code}}` to set the error's `provider_code` to a short code (never
  data). `reason` must be one of `AshOperations.Error`'s reasons.
  """
  @callback config(Transport.meta()) ::
              {:ok, config()} | {:error, Error.reason() | {Error.reason(), String.t()}}

  @doc """
  Extra headers that sign one request: the exact body bytes (`""` without a body,
  `nil` for multipart), the metadata and the config.
  """
  @callback sign(body :: binary() | nil, Transport.meta(), config()) :: [{String.t(), String.t()}]

  @optional_callbacks config: 0, config: 1, sign: 3

  @doc """
  Classify a non-2xx response. Reads codes and statuses only; must never copy a
  message or a body into the result.
  """
  @callback classify(Transport.response()) :: fields()

  defmacro __using__(_opts) do
    quote do
      @behaviour AshOperations.Transport
      @behaviour AshOperations.Http

      @impl AshOperations.Transport
      def request(request, meta),
        do: AshOperations.Http.request(__MODULE__, request, meta)

      @impl AshOperations.Http
      def classify(response), do: AshOperations.Http.by_status(response)

      defoverridable classify: 1

      @before_compile AshOperations.Http
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    unless Module.defines?(env.module, {:config, 0}) or Module.defines?(env.module, {:config, 1}) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "#{inspect(env.module)} uses AshOperations.Http but defines neither config/0 nor config/1"
    end
  end

  @doc false
  @spec request(module(), Transport.request(), Transport.meta()) ::
          {:ok, Transport.response()} | {:error, Error.t()}
  def request(transport, request, meta) do
    labels = Map.take(meta, [:provider, :operation, :method, :effect])

    :telemetry.span(meta.telemetry_prefix, labels, fn ->
      {result, attempts} =
        case config(transport, meta) do
          {:ok, config} ->
            config
            |> build_req(request, meta, transport)
            |> attempt(%{transport: transport, config: config, meta: meta}, 1)

          {:error, {reason, code}} when is_atom(reason) and is_binary(code) ->
            {{:error, error(%{reason: reason, provider_code: code}, nil, meta)}, 0}

          {:error, reason} when is_atom(reason) ->
            {{:error, error(%{reason: reason}, nil, meta)}, 0}
        end

      {result, Map.merge(labels, stop_metadata(result, attempts))}
    end)
  end

  # --- request -----------------------------------------------------------------

  defp config(transport, meta) do
    if function_exported?(transport, :config, 1),
      do: transport.config(meta),
      else: transport.config()
  end

  defp build_req(config, request, meta, transport) do
    {body_opts, bytes, body_headers} = body(request.body)
    headers = with_defaults(Map.get(config, :headers, []), body_headers)

    [
      base_url: Map.fetch!(config, :base_url),
      url: request.path,
      method: request.method,
      params: request.query,
      headers: headers ++ signature(transport, bytes, meta, config),
      retry: false,
      redirect: Map.get(config, :redirect, true),
      receive_timeout: meta.timeout
    ]
    |> put_auth(Map.get(config, :auth))
    |> Keyword.merge(body_opts)
    |> put_decoding(meta.response)
    |> Req.new()
    |> Req.merge(Map.get(config, :req_options, []))
  end

  defp put_auth(opts, {:bearer, token}), do: Keyword.put(opts, :auth, {:bearer, token})
  defp put_auth(opts, nil), do: opts

  # The JSON body is encoded here rather than by Req's `json:` option, with the same
  # encoder and the same two default headers, so the bytes a signature covers are the
  # bytes sent.
  defp body(nil), do: {[], "", []}

  defp body({:json, map}) do
    bytes = map |> Jason.encode_to_iodata!() |> IO.iodata_to_binary()
    {[body: bytes], bytes, [{"content-type", "application/json"}, {"accept", "application/json"}]}
  end

  defp body({:multipart, parts}), do: {[form_multipart: parts], nil, []}

  # A header the config already sets wins, as it did under Req's put_new_header.
  defp with_defaults(headers, defaults) do
    names = MapSet.new(headers, fn {name, _} -> String.downcase(to_string(name)) end)
    headers ++ Enum.reject(defaults, fn {name, _} -> MapSet.member?(names, name) end)
  end

  defp signature(transport, bytes, meta, config) do
    if function_exported?(transport, :sign, 3),
      do: transport.sign(bytes, meta, config),
      else: []
  end

  defp put_decoding(opts, :json),
    do: Keyword.put(opts, :decoders, json: &Jason.decode(&1, floats: :decimals))

  defp put_decoding(opts, _binary_or_none), do: Keyword.put(opts, :decode_body, false)

  defp attempt(req, ctx, n) do
    case Req.request(req) do
      {:ok, %Req.Response{status: status} = resp} when status in 200..299 ->
        {{:ok, success(resp, ctx.meta.response)}, n}

      {:ok, %Req.Response{status: status, body: body, headers: headers}} ->
        response = %{status: status, body: body, headers: headers}
        fields = ctx.transport.classify(response)
        retry_after = retry_after_ms(headers)

        decide({:status, status, fields.reason}, fields, status, retry_after, req, ctx, n)

      {:error, %Req.TransportError{reason: :timeout}} ->
        decide({:timeout}, %{reason: :timeout}, nil, nil, req, ctx, n)

      {:error, %Req.TransportError{reason: reason}} ->
        decide({:transport, reason}, %{reason: :transport}, nil, nil, req, ctx, n)

      {:error, _exception} ->
        # Dropped on purpose: Req's exceptions can carry the request.
        decide({:transport, :other}, %{reason: :transport}, nil, nil, req, ctx, n)
    end
  end

  defp decide(outcome, fields, status, retry_after, req, ctx, n) do
    opts = [
      idempotent?: ctx.meta.idempotent?,
      retry_after_ms: retry_after,
      max_attempts: Map.get(ctx.config, :max_attempts, 3),
      max_delay_ms: Map.get(ctx.config, :max_delay_ms, 10_000),
      base_backoff_ms: Map.get(ctx.config, :base_backoff_ms, 500)
    ]

    case Retry.decide(outcome, n, opts) do
      {:retry, delay} ->
        sleep(ctx.config, delay)
        attempt(req, ctx, n + 1)

      {:fail, reason} ->
        extra = if reason == :rate_limited, do: %{retry_after_ms: retry_after}, else: %{}
        {{:error, error(Map.merge(fields, Map.put(extra, :reason, reason)), status, ctx.meta)}, n}
    end
  end

  defp success(%Req.Response{status: status, body: body, headers: headers}, :binary) do
    content_type = headers |> Map.get("content-type", []) |> List.first()

    %{
      status: status,
      body: %{"content" => body, "content_type" => content_type},
      headers: headers
    }
  end

  defp success(%Req.Response{status: status, headers: headers}, :none),
    do: %{status: status, body: %{}, headers: headers}

  defp success(%Req.Response{status: status, body: body, headers: headers}, :json),
    do: %{status: status, body: body, headers: headers}

  defp error(fields, status, meta) do
    Error.exception(
      reason: fields.reason,
      status: status,
      provider_code: Map.get(fields, :provider_code),
      request_id: Map.get(fields, :request_id),
      retry_after_ms: Map.get(fields, :retry_after_ms),
      provider: meta.provider,
      operation: meta.operation
    )
  end

  defp stop_metadata({:ok, %{status: status}}, attempts),
    do: %{attempts: attempts, status: status, reason: nil}

  defp stop_metadata({:error, %Error{} = e}, attempts),
    do: %{attempts: attempts, status: e.status, reason: e.reason}

  defp sleep(config, ms) do
    case Map.get(config, :sleep) do
      fun when is_function(fun, 1) -> fun.(ms)
      _ -> Process.sleep(ms)
    end
  end

  # --- classification ----------------------------------------------------------

  @doc "Default classification: by status code alone."
  @spec by_status(Transport.response()) :: fields()
  def by_status(%{status: status}), do: %{reason: status_reason(status)}

  @doc "The reason a status code maps to."
  def status_reason(400), do: :bad_request
  def status_reason(401), do: :unauthorized
  def status_reason(402), do: :payment_required
  def status_reason(403), do: :forbidden
  def status_reason(404), do: :not_found
  def status_reason(409), do: :conflict
  def status_reason(410), do: :gone
  def status_reason(422), do: :unprocessable
  def status_reason(429), do: :rate_limited
  def status_reason(status) when status >= 500, do: :server_error
  def status_reason(_status), do: :bad_request

  # --- Retry-After -------------------------------------------------------------

  @doc false
  def retry_after_ms(headers) do
    case Map.get(headers, "retry-after") do
      [value | _] -> parse_retry_after(String.trim(value))
      _ -> nil
    end
  end

  defp parse_retry_after(value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 ->
        seconds * 1000

      _ ->
        case parse_http_date(value) do
          {:ok, at} -> max(DateTime.diff(at, DateTime.utc_now(), :millisecond), 0)
          :error -> nil
        end
    end
  end

  # IMF-fixdate, the only form RFC 9110 requires senders to use.
  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  defp parse_http_date(value) do
    with [_, day, mon, year, time] <-
           Regex.run(~r/^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}:\d{2}:\d{2}) GMT$/, value),
         month when is_integer(month) <- Enum.find_index(@months, &(&1 == mon)),
         {:ok, date} <- Date.new(String.to_integer(year), month + 1, String.to_integer(day)),
         {:ok, time} <- Time.from_iso8601(time),
         {:ok, at} <- DateTime.new(date, time, "Etc/UTC") do
      {:ok, at}
    else
      _ -> :error
    end
  end
end
