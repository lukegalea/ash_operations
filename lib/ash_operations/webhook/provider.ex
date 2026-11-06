defmodule AshOperations.Webhook.Provider do
  @moduledoc """
  What one provider contributes to the shared webhook ingress
  (`AshOperations.Webhook.Ingress`).

  A webhook is a **nudge**: it says "look at run X". An implementation never
  acts on payload values, never follows a URL found in a payload, and never
  takes a tenant or an actor from it. The follow-up reads the provider by id
  through a declared operation.

    * `verify/2` receives the exact bytes that were signed, before anything is
      decoded.
    * `dedup_key/2` returns the provider's redelivery-stable key.
    * `enqueue/2` must be idempotent per `dedup_key` and must store only ids.
    * `max_body_bytes/0` (optional) caps the body; the ingress default is 64 KiB.

  Nothing in this contract logs.
  """

  @type payload :: map()

  @callback verify(Plug.Conn.t(), raw_body :: binary()) ::
              :ok | {:error, :unauthorized | :not_configured}

  @callback dedup_key(Plug.Conn.t(), payload()) :: {:ok, String.t()} | {:error, :bad_request}

  @callback enqueue(payload(), dedup_key :: String.t()) ::
              {:ok, :enqueued | :duplicate | :ignored} | {:reject, atom()} | {:error, atom()}

  @callback max_body_bytes() :: pos_integer()

  @optional_callbacks max_body_bytes: 0
end
