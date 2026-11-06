defmodule AshOperations.Info do
  @moduledoc "Introspection over the `operations` DSL section."

  alias AshOperations.Operation
  alias Spark.Dsl.Extension

  @doc "The provider name."
  def provider(resource), do: Extension.get_opt(resource, [:operations], :provider)

  @doc "The transport module."
  def transport(resource), do: Extension.get_opt(resource, [:operations], :transport)

  @doc "The vendored spec path, or nil."
  def spec(resource), do: Extension.get_opt(resource, [:operations], :spec)

  @doc "The pinned sha-256 of the spec, or nil."
  def spec_sha256(resource), do: Extension.get_opt(resource, [:operations], :spec_sha256)

  @doc "The disclosure gate module, or nil."
  def disclosure_gate(resource), do: Extension.get_opt(resource, [:operations], :disclosure_gate)

  @doc "The telemetry span prefix."
  def telemetry_prefix(resource),
    do: Extension.get_opt(resource, [:operations], :telemetry_prefix, [:operations, :request])

  @doc "Every declared operation."
  @spec operations(Spark.Dsl.t() | module()) :: [Operation.t()]
  def operations(resource), do: Extension.get_entities(resource, [:operations])

  @doc "One declared operation by name, or nil."
  @spec operation(Spark.Dsl.t() | module(), atom()) :: Operation.t() | nil
  def operation(resource, name), do: Enum.find(operations(resource), &(&1.name == name))
end
