defmodule AshOperations.Reconcile do
  @moduledoc """
  Resolves an `:ambiguous` call: runs the operation's declared `reconcile_with`
  read and lets the caller say which result is the one it may have created.

      case Reconcile.find(Provider.Api, :upload_file, %{name_contains: "ks-" <> run_id},
             fn body -> Enum.filter(body["data"], &(&1["name"] == name)) end,
             actor: actor) do
        {:ok, file} -> adopt(file)
        :none -> safe to send again
        {:many, files} -> keep one, delete the rest
        {:error, error} -> try later
      end

  It never re-sends the ambiguous call itself. **Settle first**: a provider's
  list can lag a create by seconds, so call it only after the provider's settle
  window (a job scheduled `settle_ms` after the ambiguous attempt), never inline.
  """

  alias AshOperations.Info

  @spec find(module(), atom(), map(), (term() -> [term()]), keyword()) ::
          {:ok, term()} | :none | {:many, [term()]} | {:error, term()}
  def find(resource, operation_name, list_arguments, match, opts \\ []) do
    case Info.operation(resource, operation_name) do
      %{reconcile_with: list} when is_atom(list) and list not in [nil, :none] ->
        resource
        |> Ash.ActionInput.for_action(list, list_arguments, opts)
        |> Ash.run_action()
        |> classify(match)

      _ ->
        raise ArgumentError,
              "#{inspect(resource)}.#{operation_name} declares no reconcile_with read"
    end
  end

  defp classify({:ok, body}, match), do: matches(match.(body))
  defp classify({:error, error}, _match), do: {:error, error}

  defp matches([]), do: :none
  defp matches([one]), do: {:ok, one}
  defp matches(many) when is_list(many), do: {:many, many}
end
