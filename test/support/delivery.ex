defmodule AshOperations.Test.OpsDomain do
  @moduledoc "Test-only domain for the delivery fixture."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshOperations.Test.Delivery
  end
end

defmodule AshOperations.Test.Delivery do
  @moduledoc "The delivery macro instantiated on a bare ETS base, as a host would on its own."
  use Ash.Resource,
    domain: AshOperations.Test.OpsDomain,
    data_layer: Ash.DataLayer.Ets

  use AshOperations.Resources.Delivery, pre_check_with: AshOperations.Test.OpsDomain

  actions do
    update :reconcile_now do
      accept []
      require_atomic? false
      argument :reason, :string, allow_nil?: false
    end
  end
end

if Code.ensure_loaded?(AshA2ui.Standalone) do
  defmodule AshOperations.Test.DeliveriesUI do
    @moduledoc "The deliveries surface bound to the fixture, with a reconcile action."
    use AshOperations.A2ui.Deliveries,
      resource: AshOperations.Test.Delivery,
      reconcile_action: :reconcile_now
  end

  defmodule AshOperations.Test.ReadOnlyDeliveriesUI do
    @moduledoc "The same surface without a reconcile action."
    use AshOperations.A2ui.Deliveries,
      resource: AshOperations.Test.Delivery,
      surface_id: "read_only_deliveries"
  end
end
