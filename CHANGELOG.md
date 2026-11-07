# Changelog

## Unreleased

### Added

- `AshOperations.Resources.Delivery`: a resource macro a host instantiates on its own base
  resource, giving the inbound webhook delivery record (provider, endpoint, delivery id, event
  type, subject, signature verdict, follow-up state, timestamps; no body, no headers) with
  `record` (idempotent on `(provider, dedup_key)`), `mark_followed_up`, `awaiting_follow_up` and
  `volume_report`.
- `AshOperations.A2ui.Deliveries`: an optional ash_a2ui surface over the delivery resource (table
  with search, facets and range filter, detail, per-provider report, and an optional "Reconcile
  now" row action over a host-named action). ash_a2ui is an optional dependency; the package
  compiles and tests without it (`ASH_OPERATIONS_NO_A2UI=1`).
- `AshOperations.Gettext` and `AshOperations.Surfaces.Labels`: the surface labels as an
  `ash_operations_surfaces` gettext domain, English shipped.

- The minimum supported Elixir is now 1.20 (was 1.18).
- First extraction: the `operations` DSL, `AshOperations.Http` transport over `Req`, the shared
  retry table, typed errors, spec pinning, reconciliation, the disclosure gate and the webhook
  ingress plug.
