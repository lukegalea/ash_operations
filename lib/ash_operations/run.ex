defmodule AshOperations.Run do
  @moduledoc """
  The run step of every generated operation action:

  1. Build the request from the declaration and the cast arguments.
  2. For `discloses? true`, ask the section's disclosure gate, with the action's
     context. A refusal sends nothing.
  3. Hand the request to the section's transport, with the call in `meta.call`:
     the action's actor and tenant, and the values of its `in: :context` params.

  Returns `{:ok, body}` — the provider's decoded body — or
  `{:error, %AshOperations.Error{}}`.
  """

  use Ash.Resource.Actions.Implementation

  alias AshOperations.{Error, Info, Param, Request}

  @impl true
  def run(input, opts, context) do
    resource = input.resource
    operation = Info.operation(resource, Keyword.fetch!(opts, :operation))

    meta =
      resource |> meta(operation) |> Map.put(:call, call(operation, input.arguments, context))

    with {:ok, request} <- build(operation, input.arguments, meta),
         :ok <- gate(resource, operation, input.arguments, context, meta),
         {:ok, %{body: body}} <- Info.transport(resource).request(request, meta) do
      {:ok, body}
    end
  end

  defp build(operation, arguments, meta) do
    case Request.build(operation, arguments) do
      {:ok, request} -> {:ok, request}
      {:error, _message} -> {:error, error(:bad_request, nil, meta)}
    end
  end

  defp gate(_resource, %{discloses?: false}, _arguments, _context, _meta), do: :ok

  defp gate(resource, operation, arguments, context, meta) do
    subject = %{
      resource: resource,
      provider: meta.provider,
      operation: operation.name,
      effect: operation.effect,
      disclosure_ref: Map.fetch!(arguments, :disclosure_ref)
    }

    case Info.disclosure_gate(resource).authorize(subject, context) do
      :ok -> :ok
      {:error, code} when is_binary(code) -> {:error, error(:disclosure_refused, code, meta)}
    end
  end

  # What the transport may decide from, beside the request: who is calling, for which
  # tenant, and the arguments declared to stay off the wire.
  defp call(operation, arguments, context) do
    %{
      actor: Map.get(context, :actor),
      tenant: Map.get(context, :tenant),
      context_params:
        for %Param{in: :context, name: name} <- operation.params, into: %{} do
          {name, Map.get(arguments, name)}
        end
    }
  end

  defp meta(resource, operation) do
    %{
      provider: Info.provider(resource),
      operation: operation.name,
      method: operation.method,
      effect: operation.effect,
      idempotent?: operation.idempotent?,
      timeout: operation.timeout,
      response: operation.response,
      telemetry_prefix: Info.telemetry_prefix(resource)
    }
  end

  defp error(reason, code, meta) do
    Error.exception(
      reason: reason,
      provider_code: code,
      provider: meta.provider,
      operation: meta.operation
    )
  end
end
