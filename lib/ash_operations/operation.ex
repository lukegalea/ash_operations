defmodule AshOperations.Operation do
  @moduledoc """
  One declared provider operation: an HTTP method and a path relative to the
  transport's base URL, with `{param}` placeholders filled from `in: :path`
  params. Becomes one generic action of the same name.

  `transform/1` resolves the method-dependent defaults (`request`,
  `idempotent?`, `effect`) when the entity is built, so every reader sees
  concrete values.
  """

  defstruct [
    :name,
    :method,
    :path,
    :description,
    :request,
    :idempotent?,
    :effect,
    :reconcile_with,
    :documented_at,
    response: :json,
    timeout: 15_000,
    discloses?: false,
    params: [],
    __identifier__: nil,
    __spark_metadata__: nil
  ]

  @type method :: :get | :post | :put | :patch | :delete

  @type t :: %__MODULE__{
          name: atom(),
          method: method(),
          path: String.t(),
          description: String.t() | nil,
          request: :json | :multipart | :none,
          response: :json | :binary | :none,
          timeout: pos_integer(),
          idempotent?: boolean(),
          effect: :read | :write,
          reconcile_with: atom() | nil,
          discloses?: boolean(),
          documented_at: String.t() | nil,
          params: [AshOperations.Param.t()],
          __spark_metadata__: Spark.Dsl.Entity.spark_meta()
        }

  @placeholder ~r/\{([a-z][a-z0-9_]*)\}/

  @doc false
  def transform(%__MODULE__{method: method} = operation) do
    {:ok,
     %{
       operation
       | request: operation.request || default_request(method),
         idempotent?: default(operation.idempotent?, method in [:get, :put, :delete]),
         effect: operation.effect || if(method == :get, do: :read, else: :write)
     }}
  end

  defp default_request(method) when method in [:post, :put, :patch], do: :json
  defp default_request(_method), do: :none

  defp default(nil, value), do: value
  defp default(value, _), do: value

  @doc "The `{placeholder}` names in the path, as strings, in order."
  def placeholders(%__MODULE__{path: path}) do
    @placeholder
    |> Regex.scan(path, capture: :all_but_first)
    |> List.flatten()
  end

  @doc "The path with every placeholder name erased: `/files/{}`. Used to match a spec."
  def path_shape(path) when is_binary(path), do: Regex.replace(~r/\{[^}]+\}/, path, "{}")

  @doc false
  def placeholder_regex, do: @placeholder
end
