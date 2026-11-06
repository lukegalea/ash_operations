defmodule AshOperations.Verifiers.SpecResolves do
  @moduledoc """
  With a section `spec`, proves the declarations against the vendored document:

    * the file's sha-256 equals `spec_sha256`, so the spec cannot change
      without a reviewed pin change;
    * every operation's method exists on a path of the same shape
      (`/files/{file_id}` matches the spec's `/files/{id}`).

  An endpoint the provider does not publish fails compilation.
  """

  use Spark.Dsl.Verifier

  alias AshOperations.{Info, Spec}
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    case Info.spec(dsl_state) do
      nil -> :ok
      path -> verify_spec(dsl_state, path, Info.spec_sha256(dsl_state))
    end
  end

  defp verify_spec(dsl_state, _path, nil),
    do: fail(dsl_state, [:operations, :spec_sha256], "`spec` needs `spec_sha256` to pin it.")

  defp verify_spec(dsl_state, path, pinned) do
    case Spec.load(path) do
      {:error, message} ->
        fail(dsl_state, [:operations, :spec], message)

      {:ok, %{sha256: actual}} when actual != pinned ->
        fail(
          dsl_state,
          [:operations, :spec_sha256],
          "#{path} has sha-256 #{actual}, but spec_sha256 pins #{pinned}. Review the " <>
            "provider's change, re-check the declarations, then update the pin."
        )

      {:ok, spec} ->
        dsl_state
        |> Info.operations()
        |> Enum.reject(&Spec.endpoint?(spec, &1.method, &1.path))
        |> case do
          [] ->
            :ok

          [op | _] ->
            fail(
              dsl_state,
              [:operations, :operation, op.name],
              "#{op.method |> to_string() |> String.upcase()} #{op.path} is not in #{path}."
            )
        end
    end
  end

  defp fail(dsl_state, path, message) do
    {:error,
     DslError.exception(
       module: Verifier.get_persisted(dsl_state, :module),
       path: path,
       message: message
     )}
  end
end
