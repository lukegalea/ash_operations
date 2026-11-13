defmodule AshOperations.A2ui.Deliveries do
  @moduledoc """
  The deliveries surface: what providers have sent, newest first, with the signature verdict and
  whether anyone followed up.

  A table with search over the delivery id and subject, filters on provider, event type,
  signature verdict and follow-up state (with counts), a received-at range, and sort by
  received-at. Selecting a row shows its detail. A report counts deliveries per provider and
  verdict. Nothing on the surface shows a body or a header, because the record has none.

  ## Options

    * `:resource` (required): a resource instantiated with `AshOperations.Resources.Delivery`.
    * `:surface_id` (default `"operations_deliveries"`) and `:title`.
    * `:reconcile_action`: the name of an action on the resource, run from a row action
      "Reconcile now" that prompts for a `reason`. The host defines it: it reads the provider
      for the delivery's subject and applies the answer through its normal path, which is what
      "replay" means here (the delivery is a nudge, never a body to re-post). The action must
      take a `:reason` argument. Without the option the surface is read-only.

  ## Contract

  On the resource: the primary `:read`, the generic `:volume_report`, and, if given, the
  reconcile action with a `:reason` argument.

      defmodule MyApp.Ops.Delivery do
        # ...
        actions do
          update :reconcile_now do
            accept []
            argument :reason, :string, allow_nil?: false
            change MyApp.Ops.Changes.ReconcileDelivery
          end
        end
      end
  """

  alias AshOperations.Surfaces.Labels

  defmacro __using__(opts) do
    AshOperations.A2ui.ensure_available!(__MODULE__)

    resource = Keyword.fetch!(opts, :resource)
    surface_id = Keyword.get(opts, :surface_id, "operations_deliveries")
    title = Keyword.get_lazy(opts, :title, fn -> Labels.text(:deliveries_title) end)
    reconcile = Keyword.get(opts, :reconcile_action)

    fields = [:provider, :event_type, :signature_verdict, :state, :subject_id, :received_at]

    labelled =
      Enum.map(fields ++ [:endpoint, :dedup_key, :followed_up_at], &{&1, Labels.text(&1)})

    row_actions =
      if reconcile, do: [quote(do: row_actions(unquote([reconcile])))], else: []

    reconcile_action =
      if reconcile do
        [
          quote do
            action unquote(reconcile) do
              label unquote(Labels.text(:reconcile_now))
              prompt_title unquote(Labels.text(:reconcile_prompt_title))
              prompt_fields [:reason]
            end
          end
        ]
      else
        []
      end

    field_labels =
      for {name, label} <- labelled do
        quote do
          field unquote(name) do
            label unquote(label)
          end
        end
      end

    quote do
      use AshA2ui.Standalone

      a2ui do
        for_resource(unquote(resource))
        surface_id unquote(surface_id)
        title unquote(title)
        record_label unquote(Labels.text(:delivery_record))

        context :delivery do
          resource unquote(resource)
          picker false
        end

        query :deliveries do
          search_fields [:dedup_key, :subject_id]
          filters [:provider, :event_type, :signature_verdict, :state]
          facet_counts true
          range_filters [:received_at]
          sortable [:received_at]
          default_sort received_at: :desc
          page_size 25

          empty_state title: unquote(Labels.text(:deliveries_empty_title)),
                      message: unquote(Labels.text(:deliveries_empty_message))
        end

        component :table do
          fields unquote(fields)
          read_action :read
          query :deliveries
          unquote_splicing(row_actions)
          select_context :delivery
        end

        component :detail, :delivery_detail do
          context :delivery

          fields [
            :provider,
            :endpoint,
            :event_type,
            :dedup_key,
            :subject_id,
            :signature_verdict,
            :state,
            :received_at,
            :followed_up_at
          ]
        end

        component :report, :per_provider do
          action :volume_report
          params []
          fields [:provider, :signature_verdict, :deliveries]
        end

        unquote_splicing(reconcile_action)
        unquote_splicing(field_labels)
      end
    end
  end
end
