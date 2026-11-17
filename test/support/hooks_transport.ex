defmodule AshOperations.Test.HooksTransport do
  @moduledoc """
  A per-call transport: `config/1` reports the call it was given to the test process
  as `{:config_call, call}` and picks the base URL from the `destination` context
  param; `sign/3` reports the bytes it signed as `{:signed, bytes}` and returns an
  HMAC header over them. Redirects are not followed.
  """
  use AshOperations.Http

  @secret "synthetic-signing-secret"

  def secret, do: @secret

  @impl true
  def config(%{call: call}) do
    send(self(), {:config_call, call})

    case call.context_params do
      %{destination: "unknown"} ->
        {:error, :not_configured}

      %{destination: "refused"} ->
        {:error, {:disclosure_refused, "destination_refused"}}

      %{destination: destination} ->
        test_pid = self()

        {:ok,
         %{
           base_url: "http://#{destination}.hooks.test",
           redirect: false,
           secret: @secret,
           req_options: [plug: {Req.Test, __MODULE__}],
           sleep: fn ms -> send(test_pid, {:slept, ms}) end,
           base_backoff_ms: 1
         }}
    end
  end

  @impl true
  def sign(bytes, _meta, %{secret: secret}) do
    send(self(), {:signed, bytes})
    [{"x-signature", :crypto.mac(:hmac, :sha256, secret, bytes) |> Base.encode64()}]
  end
end
