defmodule AshOperations.Verifiers.Declaration do
  @moduledoc """
  Refuses an operation declaration that is unsafe or inconsistent:

    * **No credential is ever an argument.** A param whose name (or wire name)
      looks like a key, token, secret or authorization header is refused: the
      transport owns the credential.
    * Every `{placeholder}` has an `in: :path` param, and vice versa.
    * `in: :body` params only on `request :json`; `in: :part` only on
      `request :multipart`; neither on a `get`.
    * **Ambiguity is decided up front.** A non-idempotent operation names its
      `reconcile_with` read — an existing, idempotent `:read` operation — or says
      `reconcile_with :none`.
    * `discloses? true` needs the section's `disclosure_gate`, and no param may
      take the generated `disclosure_ref` name.
    * Without a section `spec`, every operation cites `documented_at`.

  Spark verifiers report through `--warnings-as-errors`; tests compile a
  fixture module and assert on the diagnostic.
  """

  use Spark.Dsl.Verifier

  alias AshOperations.{Info, Operation, Param}
  alias AshOperations.Transformers.AddOperationActions
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  # A normalized name (lowercase, letters only) is a credential when it is one of
  # @exact or contains one of @stems. Pagination cursors (`nextPageToken`) contain
  # none of the stems, so they stay legal.
  @exact ~w(key token auth)
  @stems ~w(apikey secret authorization bearer credential accesstoken refreshtoken idtoken
            authtoken sessiontoken connectionid providerconfigkey)

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    operations = Info.operations(dsl_state)
    by_name = Map.new(operations, &{&1.name, &1})

    section = %{
      gate?: not is_nil(Info.disclosure_gate(dsl_state)),
      spec?: not is_nil(Info.spec(dsl_state))
    }

    operations
    |> Enum.flat_map(&problems(&1, by_name, section))
    |> case do
      [] ->
        :ok

      [{operation, message} | _] ->
        {:error,
         DslError.exception(
           module: module,
           path: [:operations, :operation, operation],
           message: message
         )}
    end
  end

  defp problems(%Operation{} = op, by_name, section) do
    credentials(op) ++
      placeholders(op) ++
      locations(op) ++
      reconcile(op, by_name) ++
      disclosure(op, section) ++
      provenance(op, section)
  end

  defp credentials(op) do
    for %Param{} = p <- op.params, forbidden?(p) do
      {op.name,
       "param #{inspect(p.name)} names a credential. The transport owns the provider's " <>
         "credential; it is never an action argument."}
    end
  end

  defp placeholders(op) do
    in_path = Operation.placeholders(op)
    path_params = for %Param{in: :path} = p <- op.params, do: Atom.to_string(p.name)

    missing =
      for name <- in_path, name not in path_params do
        {op.name, "path placeholder {#{name}} has no `param :#{name}, ..., in: :path`."}
      end

    orphaned =
      for name <- path_params, name not in in_path do
        {op.name, "path param #{inspect(name)} does not appear in the path."}
      end

    missing ++ orphaned
  end

  defp locations(op) do
    body =
      for %Param{in: :body} = p <- op.params, op.request != :json do
        {op.name,
         "body param #{inspect(p.name)} needs `request :json`, not #{inspect(op.request)}."}
      end

    parts =
      for %Param{in: :part} = p <- op.params, op.request != :multipart do
        {op.name, "part param #{inspect(p.name)} needs `request :multipart`."}
      end

    get_body =
      if op.method == :get and op.request != :none,
        do: [{op.name, "a get operation sends no body; drop `request #{inspect(op.request)}`."}],
        else: []

    body ++ parts ++ get_body
  end

  defp reconcile(%Operation{idempotent?: true, reconcile_with: nil}, _by_name), do: []
  defp reconcile(%Operation{reconcile_with: :none}, _by_name), do: []

  defp reconcile(%Operation{idempotent?: false, reconcile_with: nil} = op, _by_name) do
    [
      {op.name,
       "#{op.name} is not idempotent: a timeout or 5xx leaves it ambiguous. Name the read that " <>
         "finds what it may have created (`reconcile_with :list_...`), or opt out with " <>
         "`reconcile_with :none`."}
    ]
  end

  defp reconcile(%Operation{reconcile_with: target} = op, by_name) do
    case Map.get(by_name, target) do
      %Operation{idempotent?: true, effect: :read} ->
        []

      %Operation{} ->
        [{op.name, "reconcile_with #{inspect(target)} must be an idempotent read operation."}]

      nil ->
        [{op.name, "reconcile_with #{inspect(target)} is not a declared operation."}]
    end
  end

  defp disclosure(%Operation{discloses?: false} = op, _section), do: collides(op)

  defp disclosure(%Operation{discloses?: true} = op, %{gate?: gate?}) do
    missing =
      if gate?,
        do: [],
        else: [
          {op.name, "discloses? true needs a `disclosure_gate` in the operations section."}
        ]

    missing ++ collides(op)
  end

  defp collides(op) do
    for %Param{name: name} <- op.params, name == AddOperationActions.disclosure_argument() do
      {op.name, "param #{inspect(name)} collides with the generated disclosure argument."}
    end
  end

  defp provenance(_op, %{spec?: true}), do: []
  defp provenance(%Operation{documented_at: url}, _) when is_binary(url), do: []

  defp provenance(op, _section) do
    [
      {op.name,
       "no `spec` in the operations section, so #{op.name} must cite `documented_at` — the " <>
         "provider documentation it was declared from."}
    ]
  end

  defp forbidden?(%Param{} = param) do
    Enum.any?([Atom.to_string(param.name), Param.wire_name(param)], fn name ->
      normalized = normalize(name)
      normalized in @exact or Enum.any?(@stems, &String.contains?(normalized, &1))
    end)
  end

  defp normalize(name), do: name |> String.downcase() |> String.replace(~r/[^a-z]/, "")
end
