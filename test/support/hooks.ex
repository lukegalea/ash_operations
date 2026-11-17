defmodule AshOperations.Test.Hooks do
  @moduledoc """
  A synthetic provider whose destination and credential are chosen per call: the
  operation takes an `in: :context` param the transport reads, and the transport signs
  the exact body bytes. For `test/outbound_context_test.exs`.
  """
  use Ash.Resource,
    domain: AshOperations.Test.Domain,
    extensions: [AshOperations]

  operations do
    provider :hooks
    transport AshOperations.Test.HooksTransport
    telemetry_prefix [:operations_test, :hooks]

    operation :deliver, :post, "/" do
      idempotent? true
      response :none
      documented_at "https://hooks.test/docs"
      param :destination, :string, in: :context, allow_nil?: false
      param :event, :string, in: :body, allow_nil?: false
      param :data, :map, in: :body
    end

    operation :peek, :get, "/peek" do
      documented_at "https://hooks.test/docs"
      param :destination, :string, in: :context, allow_nil?: false
    end
  end

  resource do
    require_primary_key? false
  end
end
