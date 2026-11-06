defmodule AshOperations.Transport do
  @moduledoc """
  The one module per provider that speaks HTTP.

  `request/2` receives a built request and the operation's metadata and returns
  the provider's status and decoded body, or a typed
  `AshOperations.Error`. Retrying, classification and
  telemetry are the transport's job; `AshOperations.Http`
  implements all three over `Req` and is what a provider transport normally
  `use`s.
  """

  alias AshOperations.Error

  @type request :: %{
          required(:method) => :get | :post | :put | :patch | :delete,
          required(:path) => String.t(),
          required(:query) => [{String.t(), String.t()}],
          required(:body) => nil | {:json, map()} | {:multipart, list()}
        }

  @type meta :: %{
          required(:provider) => atom(),
          required(:operation) => atom(),
          required(:method) => atom(),
          required(:effect) => :read | :write,
          required(:idempotent?) => boolean(),
          required(:timeout) => pos_integer(),
          required(:response) => :json | :binary | :none,
          required(:telemetry_prefix) => [atom()]
        }

  @type response :: %{status: pos_integer(), body: term(), headers: map()}

  @callback request(request(), meta()) :: {:ok, response()} | {:error, Error.t()}
end
