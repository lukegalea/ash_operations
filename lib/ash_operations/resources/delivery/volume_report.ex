defmodule AshOperations.Resources.Delivery.VolumeReport do
  @moduledoc """
  Run module of `volume_report` on a delivery resource: one row per provider and signature
  verdict with the number of deliveries, read as the actor under the host's policies.

  The rows are counted in memory from two selected columns, which suits the retention window of
  a delivery log. A host that keeps years of deliveries narrows the read with its own policy
  scope or replaces the action.
  """
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, context) do
    rows =
      input.resource
      |> Ash.Query.select([:provider, :signature_verdict])
      |> Ash.Query.for_read(:read, %{},
        actor: context.actor,
        tenant: context.tenant,
        authorize?: context.authorize?
      )
      |> Ash.read()

    with {:ok, deliveries} <- rows do
      {:ok,
       deliveries
       |> Enum.frequencies_by(&{&1.provider, &1.signature_verdict})
       |> Enum.map(fn {{provider, verdict}, count} ->
         %{provider: provider, signature_verdict: verdict, deliveries: count}
       end)
       |> Enum.sort_by(&{&1.provider, &1.signature_verdict})}
    end
  end
end
