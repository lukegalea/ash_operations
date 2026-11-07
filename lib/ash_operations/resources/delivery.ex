defmodule AshOperations.Resources.Delivery do
  # credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks
  @moduledoc """
  The inbound webhook delivery record, as a resource macro a host instantiates on its own base
  resource. The package owns no table: the host declares the resource, its data layer, its
  domain and its policies, and the macro adds the attributes, the identity and the actions.

      defmodule MyApp.Ops.Delivery do
        use Ash.Resource,
          domain: MyApp.Ops,
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        use AshOperations.Resources.Delivery

        postgres do
          table "ops_deliveries"
          repo MyApp.Repo
        end

        policies do
          # your grants govern record, mark_followed_up and the reads
        end
      end

  A webhook is a signed nudge: it says "look at subject X". A delivery therefore holds only what
  an operator and the follow-up need, never a body and never a header.

  | Attribute | Notes |
  |---|---|
  | `provider` | the declared provider name; with `dedup_key` it is the identity |
  | `endpoint` | which of the provider's endpoints received it; optional |
  | `dedup_key` | the provider's redelivery-stable event id |
  | `event_type` | the provider's name for what happened; optional |
  | `subject_id` | what the nudge is about, and what a reconcile reads. Untrusted until read |
  | `signature_verdict` | `valid`, `invalid`, `stale` or `unknown_secret`; defaults to `valid`, the only verdict a receiver that rejects bad signatures can record. The word "verified" is deliberately not used |
  | `state` | `received`, `followed_up` or `ignored` |
  | `received_at`, `followed_up_at` | timestamps |

  ## Options

    * `:pre_check_with`: a domain to check the `(provider, dedup_key)` identity with, for a data
      layer that cannot check identities natively (ETS, in tests). Not needed on Postgres.
    * `:subject_required?`: `true` makes `subject_id` mandatory (`allow_nil? false`). Default
      `false`, since some providers nudge without naming a subject.
    * `:settle_changes`: a list of changes (modules or `{module, opts}`) appended to
      `mark_followed_up`, after the built-in settle. A host whose follow-up does work (reads the
      provider, enqueues a reconcile) defines `update :follow_up` as `mark_followed_up` plus its
      change, instead of setting `state` and `followed_up_at` itself. The built-in changes have
      already set `state` and `followed_up_at` when yours run, so yours may override `state`
      (for instance in a `before_transaction` hook, once it has read the provider).
      Spark rejects a second action of the same name, so this option is the way to layer on
      `mark_followed_up`; to run it under another name, wrap it in a host action that calls it.

  ## Actions

    * `record` (create). Idempotent on `(provider, dedup_key)`: a redelivery returns the stored
      row unchanged, so the receiver never has to check first.
    * `mark_followed_up` (update). The one settle path: sets `state` (argument `outcome`,
      `:followed_up` by default or `:ignored`) and `followed_up_at`, then runs `:settle_changes`.
      A delivery that is no longer `received` is left exactly as it is and the stored record is
      returned, with none of the settle changes run, so a retried job cannot settle twice or
      move `followed_up_at`.
    * `read`, the primary read, and `awaiting_follow_up`, the deliveries still `received`.
    * `volume_report` (generic). Counts of deliveries per provider and signature verdict, the
      rows of the operator surface's report (`AshOperations.A2ui.Deliveries`).

  No action accepts or takes an argument named for a body, payload or header.

  ## Functions

    * `recorded?(provider, dedup_key)`: whether a delivery with that identity is stored. A cheap
      early return for a webhook path that wants to skip work for a redelivery. It reads with
      `authorize?: false` because it runs in the receiving path before any actor exists, and it
      returns a boolean, never a row.

  ## Adopting the macro on an existing table

  `received_at` and `signature_verdict` are required columns with no database default the
  generator can write for a function default, so adding them to a table that already has rows
  needs `migration_defaults` in the `postgres` block (then `mix ash.codegen`; do not hand-write
  the migration). This quoting is what generated a working migration:

      postgres do
        table "ops_deliveries"
        repo MyApp.Repo

        migration_defaults received_at: ~S|fragment("(now() AT TIME ZONE 'utc')")|,
                           signature_verdict: ~S|"valid"|
      end

  The values are Elixir source for the migration, hence the `~S` sigils: `received_at` becomes
  `default: fragment("(now() AT TIME ZONE 'utc')")` and `signature_verdict` becomes
  `default: "valid"`. Existing rows read as received now and with the `valid` verdict. A
  `subject_id` column that was `null: false` becomes nullable in the same generated migration
  unless you pass `subject_required?: true`.

  ## Host-owned

  Policies, tenancy, audit, ownership, archival and the data layer. A host that follows up with a
  job adds its own trigger over `awaiting_follow_up`.
  """

  defmacro __using__(opts) do
    pre_check_with = Keyword.get(opts, :pre_check_with)
    subject_required? = Keyword.get(opts, :subject_required?, false)

    settle_changes =
      for change <- Keyword.get(opts, :settle_changes, []) do
        quote do
          change unquote(change), where: AshOperations.Resources.Delivery.Unsettled
        end
      end

    quote location: :keep do
      attributes do
        uuid_primary_key :id

        attribute :provider, :string do
          allow_nil? false
          public? true
          constraints max_length: 64
        end

        attribute :endpoint, :string do
          public? true
          constraints max_length: 128
        end

        attribute :dedup_key, :string do
          allow_nil? false
          public? true
          constraints max_length: 128
        end

        attribute :event_type, :string do
          public? true
          constraints max_length: 128
        end

        attribute :subject_id, :string do
          allow_nil? not unquote(subject_required?)
          public? true
          constraints max_length: 128
          description "What the provider says to look at. Untrusted until read."
        end

        attribute :signature_verdict, :atom do
          allow_nil? false
          public? true
          default :valid
          constraints one_of: [:valid, :invalid, :stale, :unknown_secret]
        end

        attribute :state, :atom do
          allow_nil? false
          public? true
          default :received
          constraints one_of: [:received, :followed_up, :ignored]
        end

        attribute :received_at, :utc_datetime_usec do
          allow_nil? false
          public? true
          writable? false
          default &DateTime.utc_now/0
        end

        attribute :followed_up_at, :utc_datetime_usec do
          public? true
          writable? false
        end
      end

      identities do
        identity :delivery, [:provider, :dedup_key], pre_check_with: unquote(pre_check_with)
      end

      actions do
        defaults [:read]

        create :record do
          description "Record a delivery once, by the provider's own redelivery-stable key."
          accept [:provider, :endpoint, :dedup_key, :event_type, :subject_id, :signature_verdict]
          upsert? true
          upsert_identity :delivery
          # A redelivery rewrites nothing that matters; naming one field keeps the stored row
          # coming back on every data layer.
          upsert_fields [:dedup_key]
        end

        update :mark_followed_up do
          description "Settle a delivery: followed up, or ignored because there was nothing to do."
          accept []
          require_atomic? false

          argument :outcome, :atom do
            default :followed_up
            allow_nil? false
            constraints one_of: [:followed_up, :ignored]
          end

          # A delivery already settled is left as it is: every change below is guarded by `Unsettled`, so the
          # update is a no-op that returns the stored row.
          change set_attribute(:state, expr(^arg(:outcome))),
            where: AshOperations.Resources.Delivery.Unsettled

          change set_attribute(:followed_up_at, &DateTime.utc_now/0),
            where: AshOperations.Resources.Delivery.Unsettled

          unquote_splicing(settle_changes)
        end

        read :awaiting_follow_up do
          description "Deliveries recorded and not yet followed up, oldest first."
          filter expr(^ref(:state) == :received)
          prepare build(sort: [received_at: :asc])
        end

        action :volume_report, {:array, :map} do
          description "Deliveries per provider and signature verdict."
          run AshOperations.Resources.Delivery.VolumeReport
        end
      end

      @doc "Whether a delivery with this provider and dedup key is already recorded."
      @spec recorded?(String.t(), String.t()) :: boolean()
      def recorded?(provider_name, dedup_key_value) do
        __MODULE__
        |> Ash.Query.filter_input(%{provider: provider_name, dedup_key: dedup_key_value})
        |> Ash.exists?(authorize?: false)
      end
    end
  end
end
