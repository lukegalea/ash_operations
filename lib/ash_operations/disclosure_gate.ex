defmodule AshOperations.DisclosureGate do
  @moduledoc """
  The host's decision on whether a `discloses? true` operation may send.

  Called inside the generated action, after the arguments are cast and before
  the transport is called, with the action's context (actor, tenant). A refusal
  sends nothing and fails the action with reason `:disclosure_refused`;
  `code` becomes the error's `provider_code`, so it must be a short code, never
  data.

  The gate decides from the host's own records (the `disclosure_ref` names one);
  it never inspects the payload.
  """

  @type subject :: %{
          resource: module(),
          provider: atom(),
          operation: atom(),
          effect: :read | :write,
          disclosure_ref: String.t()
        }

  @callback authorize(subject(), context :: struct() | map()) ::
              :ok | {:error, code :: String.t()}
end
