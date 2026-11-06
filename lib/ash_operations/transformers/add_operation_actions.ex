defmodule AshOperations.Transformers.AddOperationActions do
  @moduledoc """
  Turns each declared `operation` into one generic action plus a code
  interface of the same name, and marks the vendored spec as an external
  resource so editing it recompiles the declaring module.

  A `discloses? true` operation gets one extra required argument,
  `disclosure_ref`: the host's reference to the record that justifies sending.
  """

  use Spark.Dsl.Transformer

  alias Ash.Resource.Builder
  alias AshOperations.{Info, Operation, Param, Run}
  alias Spark.Dsl.Transformer

  @disclosure_argument :disclosure_ref

  @doc false
  def disclosure_argument, do: @disclosure_argument

  # Actions must exist before Ash derives primary actions, input caches and
  # code interfaces from them.
  @impl true
  def before?(transformer) do
    transformer |> inspect() |> String.starts_with?("Ash.Resource.Transformers.")
  end

  @impl true
  def transform(dsl_state) do
    dsl_state = external_resource(dsl_state, Info.spec(dsl_state))

    dsl_state
    |> Info.operations()
    |> Enum.reduce_while({:ok, dsl_state}, fn operation, {:ok, dsl} ->
      case add_operation(dsl, operation) do
        {:ok, dsl} -> {:cont, {:ok, dsl}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp external_resource(dsl_state, nil), do: dsl_state

  defp external_resource(dsl_state, path) do
    Transformer.eval(dsl_state, [], quote(do: @external_resource(unquote(path))))
  end

  defp add_operation(dsl, %Operation{} = operation) do
    with {:ok, arguments} <- build_arguments(operation),
         {:ok, dsl} <-
           Builder.add_action(dsl, :action, operation.name,
             returns: :map,
             description: description(operation),
             arguments: arguments,
             run: {Run, operation: operation.name}
           ) do
      Builder.add_interface(dsl, operation.name, action: operation.name)
    end
  end

  defp build_arguments(%Operation{params: params} = operation) do
    disclosure =
      if operation.discloses?,
        do: [
          Builder.build_action_argument(@disclosure_argument, :string,
            allow_nil?: false,
            description:
              "The host's reference to the record that justifies sending this data. " <>
                "Checked by the disclosure gate before anything is sent."
          )
        ],
        else: []

    (Enum.map(params, &build_param/1) ++ disclosure)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, argument}, {:ok, acc} -> {:cont, {:ok, [argument | acc]}}
      {:error, error}, _ -> {:halt, {:error, error}}
    end)
    |> case do
      {:ok, arguments} -> {:ok, Enum.reverse(arguments)}
      error -> error
    end
  end

  defp build_param(%Param{} = param) do
    opts =
      [
        allow_nil?: param.allow_nil? and param.in != :path,
        constraints: param.constraints,
        description: param.description,
        sensitive?: param.sensitive?
      ]
      |> maybe_put(:default, param.default)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    Builder.build_action_argument(param.name, param.type, opts)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp description(%Operation{description: nil, method: method, path: path}),
    do: "#{method |> to_string() |> String.upcase()} #{path}"

  defp description(%Operation{description: description}), do: description
end
