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
    * `payload_shape/0` (optional) is `:object` (the default) or `:array`, for a
      provider that posts a batch of events as one top-level JSON array. The
      payload `dedup_key/2` and `enqueue/2` receive is then a list.

  Nothing in this contract logs.
  """

  @type payload :: map() | list()

  @callback verify(Plug.Conn.t(), raw_body :: binary()) ::
              :ok | {:error, :unauthorized | :not_configured}

  @callback dedup_key(Plug.Conn.t(), payload()) :: {:ok, String.t()} | {:error, :bad_request}

  @callback enqueue(payload(), dedup_key :: String.t()) ::
              {:ok, :enqueued | :duplicate | :ignored} | {:reject, atom()} | {:error, atom()}

  @callback max_body_bytes() :: pos_integer()

  @callback payload_shape() :: :object | :array

  @optional_callbacks max_body_bytes: 0, payload_shape: 0
end
