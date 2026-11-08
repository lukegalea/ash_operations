if Code.ensure_loaded?(AshA2ui.Standalone) do
  defmodule AshOperations.A2ui.DeliveriesTest do
    use ExUnit.Case, async: true

    alias AshOperations.Test.DeliveriesUI
    alias AshOperations.Test.Delivery
    alias AshOperations.Test.ReadOnlyDeliveriesUI

    @moduletag :a2ui

    setup do
      provider = "surface-#{System.unique_integer([:positive])}"

      for {key, verdict} <- [{"e1", :valid}, {"e2", :valid}, {"e3", :invalid}] do
        Delivery
        |> Ash.Changeset.for_create(:record, %{
          provider: provider,
          dedup_key: "#{provider}-#{key}",
          subject_id: "sub-#{key}",
          event_type: "item.changed",
          signature_verdict: verdict
        })
        |> Ash.create!()
      end

      %{provider: provider}
    end

    defp json(term), do: term |> Jason.encode!() |> Jason.decode!()

    defp component_ids(messages) do
      messages
      |> json()
      |> inspect(limit: :infinity)
    end

    test "the surface compiles and builds" do
      messages = AshA2ui.Info.build_surface(DeliveriesUI, authorize?: false)

      assert is_list(messages) and messages != []
      text = component_ids(messages)

      assert text =~ "Webhook deliveries"
      assert text =~ "Signature"
      assert text =~ "Delivery id"
      assert text =~ "Reconcile now"
    end

    test "the table payload carries the delivery rows", %{provider: provider} do
      data = AshA2ui.Info.build_data_model(DeliveriesUI, authorize?: false) |> json()
      text = inspect(data, limit: :infinity)

      assert text =~ provider
      assert text =~ "sub-e1"
      assert text =~ "item.changed"
      assert text =~ "invalid"
    end

    test "the query allowlists the declared filters and sort only" do
      view = AshA2ui.ResolvedView.resolve(DeliveriesUI)
      query = view.query

      assert Enum.sort(query.filters) == [:event_type, :provider, :signature_verdict, :state]
      assert query.sortable == [:received_at]
      assert query.search_fields == [:dedup_key, :subject_id]
    end

    test "the report component runs volume_report", %{provider: provider} do
      view = AshA2ui.ResolvedView.resolve(DeliveriesUI)
      assert [%{action: :volume_report, fields: fields}] = view.reports
      assert fields == [:provider, :signature_verdict, :deliveries]

      rows =
        Delivery
        |> Ash.ActionInput.for_action(:volume_report, %{})
        |> Ash.run_action!()
        |> Enum.filter(&(&1.provider == provider))

      assert Enum.map(rows, & &1.deliveries) |> Enum.sum() == 3
    end

    test "the reconcile row action is only on the surface when named" do
      with_action = AshA2ui.ResolvedView.resolve(DeliveriesUI)
      without = AshA2ui.ResolvedView.resolve(ReadOnlyDeliveriesUI)

      assert inspect(with_action) =~ "reconcile_now"
      refute inspect(without) =~ "reconcile_now"
    end
  end
end
