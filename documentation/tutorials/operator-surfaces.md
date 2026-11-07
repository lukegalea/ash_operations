# Operator surfaces

A webhook is a signed nudge. Once your ingress has verified one, an operator wants to answer
three questions: what did the provider send, did we act on it, and what is the volume per
provider. AshOperations ships the pieces for that without owning a table or a screen:

- `AshOperations.Resources.Delivery`, a resource macro that gives your own resource the delivery
  record.
- `AshOperations.A2ui.Deliveries`, a macro that expands to an [ash_a2ui](https://github.com/lukegalea/ash_a2ui)
  surface over that resource. ash_a2ui is an optional dependency.

Examples use two synthetic providers, `acme-registry` and `acme-docs`.

## The delivery record

Declare the resource on your own base, with your data layer, domain and policies. The macro adds
the attributes, the identity and the actions.

```elixir
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
```

Then run `mix ash.codegen add_deliveries` for the migration.

A delivery holds the provider, an optional endpoint and event type, the provider's
redelivery-stable `dedup_key`, a `subject_id` (what the nudge is about), a `signature_verdict`
(`valid`, `invalid`, `stale` or `unknown_secret`), a follow-up `state` (`received`,
`followed_up`, `ignored`) and the `received_at` and `followed_up_at` timestamps. It holds no
body and no header, and no action accepts either: an operator console that can show a payload is
a place a payload can leak from. "Verified" is deliberately not a verdict word.

Record from your provider's `enqueue/2` callback. A redelivery returns the stored row unchanged,
so there is nothing to check first:

```elixir
def enqueue(%{"itemId" => id}, key) do
  attrs = %{provider: "acme-registry", dedup_key: key, subject_id: id, event_type: "item.changed"}

  case MyApp.Ops.record_delivery(attrs, actor: system_actor()) do
    {:ok, _delivery} -> {:ok, :enqueued}
    {:error, _} -> {:error, :insert_failed}
  end
end
```

`mark_followed_up` settles a delivery (`outcome: :followed_up`, or `:ignored` when there was
nothing to do). `awaiting_follow_up` reads the deliveries still `received`, oldest first, which is
what a follow-up job's trigger reads.

On a data layer that cannot check identities natively (ETS, in tests) pass the domain:
`use AshOperations.Resources.Delivery, pre_check_with: MyApp.Ops`.

## The deliveries surface

```elixir
defmodule MyAppWeb.A2ui.DeliveriesUI do
  use AshOperations.A2ui.Deliveries,
    resource: MyApp.Ops.Delivery,
    reconcile_action: :reconcile_now
end
```

The surface is a table of deliveries, newest first, with search over the delivery id and
subject, filters on provider, event type, signature verdict and follow-up state (with counts), a
received-at range and sort by received-at; a detail for the selected row; and a report of
deliveries per provider and verdict. Mounting it (a route, a shell entry) is yours, as with any
`AshA2ui.Standalone` module.

### Reconcile now

"Replay" of a nudge never re-posts a stored body, because there is none. The row action
"Reconcile now" prompts for a reason and runs an action **you** define on the resource: it reads
the provider for the delivery's subject and applies the answer through your normal path.

```elixir
update :reconcile_now do
  accept []
  argument :reason, :string, allow_nil?: false
  change MyApp.Ops.Changes.ReconcileDelivery
end
```

Omit `:reconcile_action` and the surface is read-only. The action runs under your policies, so
who may reconcile is a grant, not a flag.

### Options

| Option | Default | Meaning |
|---|---|---|
| `:resource` | required | a resource using `AshOperations.Resources.Delivery` |
| `:surface_id` | `"operations_deliveries"` | the A2UI surface id |
| `:title` | "Webhook deliveries" | the surface title |
| `:reconcile_action` | none | name of your action with a `:reason` argument |

## Without ash_a2ui

The resource macro, the labels and the rest of the package do not reference ash_a2ui. Only
expanding `use AshOperations.A2ui.Deliveries` needs it, and without it that raises a
`CompileError` naming the dependency to add. The package itself is tested both ways:
`ASH_OPERATIONS_NO_A2UI=1 mix deps.get && ASH_OPERATIONS_NO_A2UI=1 mix test` builds in
`_build_no_a2ui` with its own lockfile. The surface needs ash_a2ui at `bff7ed0` or later (a
`display :timeline` table) and the package pins its lock to a newer commit.

## Labels and translation

Every label the surface writes is a message in the `ash_operations_surfaces` gettext domain of
`AshOperations.Gettext`, looked up through `AshOperations.Surfaces.Labels`. The shipped catalog
is English. To translate, add `priv/gettext/<locale>/LC_MESSAGES/ash_operations_surfaces.po` to
your application, or translate through ash_a2ui's metadata domain
(`mix ash_a2ui.gettext.extract_metadata`), which sees the same labels.
