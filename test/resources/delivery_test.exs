defmodule AshOperations.Resources.DeliveryTest do
  use ExUnit.Case, async: true

  alias Ash.Resource.Info
  alias AshOperations.Test.Delivery

  defp unique, do: "evt-#{System.unique_integer([:positive])}"

  defp record!(attrs \\ %{}) do
    base = %{provider: "acme-registry", dedup_key: unique(), subject_id: "sub-1"}

    Delivery
    |> Ash.Changeset.for_create(:record, Map.merge(base, attrs))
    |> Ash.create!()
  end

  test "record stores the nudge with its defaults" do
    delivery = record!(%{event_type: "item.changed", endpoint: "primary"})

    assert delivery.state == :received
    assert delivery.signature_verdict == :valid
    assert %DateTime{} = delivery.received_at
    assert delivery.followed_up_at == nil
    assert delivery.event_type == "item.changed"
  end

  test "record is idempotent on (provider, dedup_key)" do
    key = unique()
    first = record!(%{dedup_key: key})
    second = record!(%{dedup_key: key, subject_id: "other"})

    assert second.id == first.id
    assert second.received_at == first.received_at
    assert second.subject_id == "sub-1"

    other_provider = record!(%{dedup_key: key, provider: "acme-docs"})
    refute other_provider.id == first.id
  end

  test "a signature verdict is one of four, never 'verified'" do
    assert record!(%{signature_verdict: :stale}).signature_verdict == :stale

    assert_raise Ash.Error.Invalid, fn -> record!(%{signature_verdict: :verified}) end
  end

  test "received_at cannot be supplied" do
    assert_raise Ash.Error.Invalid, fn -> record!(%{received_at: ~U[2020-01-01 00:00:00Z]}) end
  end

  test "mark_followed_up settles the delivery, followed up by default" do
    delivery = record!()
    settled = delivery |> Ash.Changeset.for_update(:mark_followed_up, %{}) |> Ash.update!()

    assert settled.state == :followed_up
    assert %DateTime{} = settled.followed_up_at

    ignored =
      record!()
      |> Ash.Changeset.for_update(:mark_followed_up, %{outcome: :ignored})
      |> Ash.update!()

    assert ignored.state == :ignored

    assert_raise Ash.Error.Invalid, fn ->
      record!()
      |> Ash.Changeset.for_update(:mark_followed_up, %{outcome: :received})
      |> Ash.update!()
    end
  end

  test "awaiting_follow_up lists only received deliveries, oldest first" do
    a = record!(%{provider: "queue-test"})
    b = record!(%{provider: "queue-test"})
    done = record!(%{provider: "queue-test"})
    done |> Ash.Changeset.for_update(:mark_followed_up, %{}) |> Ash.update!()

    ids =
      Delivery
      |> Ash.Query.for_read(:awaiting_follow_up)
      |> Ash.read!()
      |> Enum.filter(&(&1.provider == "queue-test"))
      |> Enum.map(& &1.id)

    assert ids == [a.id, b.id]
  end

  test "volume_report counts deliveries per provider and verdict" do
    provider = "report-#{System.unique_integer([:positive])}"
    record!(%{provider: provider})
    record!(%{provider: provider})
    record!(%{provider: provider, signature_verdict: :invalid})

    rows =
      Delivery
      |> Ash.ActionInput.for_action(:volume_report, %{})
      |> Ash.run_action!()
      |> Enum.filter(&(&1.provider == provider))

    assert rows == [
             %{provider: provider, signature_verdict: :invalid, deliveries: 1},
             %{provider: provider, signature_verdict: :valid, deliveries: 2}
           ]
  end

  test "no action accepts, or takes an argument for, a body or headers" do
    forbidden = ~w(body payload headers header raw)

    for action <- Info.actions(Delivery) do
      names =
        Enum.map(action.arguments, & &1.name) ++ Map.get(action, :accept, [])

      for name <- names do
        refute Enum.any?(forbidden, &String.contains?(Atom.to_string(name), &1)),
               "#{action.name} takes #{name}"
      end
    end

    attributes = Enum.map(Info.attributes(Delivery), &Atom.to_string(&1.name))
    refute Enum.any?(attributes, &String.contains?(&1, ~w(body payload header)))
  end

  test "mark_followed_up on a settled delivery is a no-op returning the stored row" do
    settled = record!() |> Ash.Changeset.for_update(:mark_followed_up, %{}) |> Ash.update!()

    again =
      settled
      |> Ash.Changeset.for_update(:mark_followed_up, %{outcome: :ignored})
      |> Ash.update!()

    assert again.state == :followed_up
    assert again.followed_up_at == settled.followed_up_at
  end

  test "subject_id is optional by default and required with subject_required?: true" do
    assert Info.attribute(Delivery, :subject_id).allow_nil?
    refute Info.attribute(AshOperations.Test.StrictDelivery, :subject_id).allow_nil?

    assert_raise Ash.Error.Invalid, fn ->
      AshOperations.Test.StrictDelivery
      |> Ash.Changeset.for_create(:record, %{provider: "p", dedup_key: unique()})
      |> Ash.create!()
    end
  end

  test "settle_changes layer on mark_followed_up after the built-in settle" do
    delivery =
      AshOperations.Test.StrictDelivery
      |> Ash.Changeset.for_create(:record, %{
        provider: "p",
        dedup_key: unique(),
        subject_id: "s"
      })
      |> Ash.create!()

    settled = delivery |> Ash.Changeset.for_update(:mark_followed_up, %{}) |> Ash.update!()
    assert settled.state == :ignored
    assert %DateTime{} = settled.followed_up_at

    # settled now: the host change does not run again
    again =
      settled
      |> Ash.Changeset.for_update(:mark_followed_up, %{outcome: :followed_up})
      |> Ash.update!()

    assert again.state == :ignored
    assert again.followed_up_at == settled.followed_up_at
  end

  test "recorded?/2 reports whether the identity is stored" do
    key = unique()
    refute Delivery.recorded?("acme-registry", key)
    record!(%{dedup_key: key})
    assert Delivery.recorded?("acme-registry", key)
    refute Delivery.recorded?("acme-docs", key)
  end
end
