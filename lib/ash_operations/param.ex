defmodule AshOperations.Param do
  @moduledoc """
  One input to a declared operation: one argument on the generated action and
  one field on the request (query parameter, path segment, top-level JSON body
  field or multipart part).

  `name` is the Ash argument (snake_case); `as` is the provider's own name for
  it (`"nameContains"`), defaulting to `name`.
  """

  defstruct [
    :name,
    :type,
    :as,
    :default,
    :description,
    in: :query,
    allow_nil?: true,
    sensitive?: false,
    constraints: [],
    __identifier__: nil,
    __spark_metadata__: nil
  ]

  @type location :: :query | :path | :body | :part

  @type t :: %__MODULE__{
          name: atom(),
          type: Ash.Type.t(),
          as: String.t() | nil,
          in: location(),
          allow_nil?: boolean(),
          sensitive?: boolean(),
          default: term(),
          constraints: keyword(),
          description: String.t() | nil,
          __spark_metadata__: Spark.Dsl.Entity.spark_meta()
        }

  @doc "The provider's name for this field."
  def wire_name(%__MODULE__{as: nil, name: name}), do: Atom.to_string(name)
  def wire_name(%__MODULE__{as: as}), do: as
end
