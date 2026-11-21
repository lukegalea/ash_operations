# Changelog

## Unreleased

- The installer's documentation helper moved out of the `Mix.Tasks` namespace, so generated task
  listings no longer show it as a task.
- The webhook ingress answers 408 when the body read times out. Bandit raises with an atom
  `plug_status` (`:request_timeout`); the status is now resolved with `Plug.Exception.status/1`.
- The minimum supported Elixir is now 1.20 (was 1.18).
- First extraction: the `operations` DSL, `AshOperations.Http` transport over `Req`, the shared
  retry table, typed errors, spec pinning, reconciliation, the disclosure gate and the webhook
  ingress plug.

### Added

- `AshOperations.Webhook.Provider`: an optional `payload_shape/0` (`:object`, the default, or
  `:array`), for a provider that posts a batch of events as one top-level JSON array. The ingress
  answers 400 when the top-level value has the other shape.
- `AshOperations.Webhook.Signature.valid_ecdsa_sha256?/3`: verifies a base64 DER ECDSA signature
  over SHA-256 against any one of several public keys (base64 DER SubjectPublicKeyInfo or PEM),
  for providers that sign webhooks with a key pair rather than a shared secret.
- The transport sees the call: `meta.call` holds the action's `actor`, `tenant` and the values of
  its `in: :context` params. A new param location, `in: :context`, is an action argument that is
  never put on the wire.
- `AshOperations.Http`: an optional `config/1`, called with the operation's metadata instead of
  `config/0` when a transport defines it, so the base URL and credential can depend on the call. It
  may refuse with `{:error, reason}` or `{:error, {reason, code}}`. A transport defining neither
  `config/0` nor `config/1` no longer compiles.
- `AshOperations.Http`: an optional `sign/3` callback receives the exact body bytes sent and
  returns extra headers. A JSON body is now encoded by the transport rather than by Req's `json:`
  option, with the same encoder and the same default `content-type` and `accept` headers, so the
  bytes on the wire are unchanged.
- `AshOperations.Http`: a `redirect` config key (default `true`, Req's behaviour). `false` leaves
  a 3xx unfollowed, failing with reason `:bad_request` and its status.

- `AshOperations.Resources.Delivery`: a resource macro a host instantiates on its own base
  resource, giving the inbound webhook delivery record (provider, endpoint, delivery id, event
  type, subject, signature verdict, follow-up state, timestamps; no body, no headers) with
  `record` (idempotent on `(provider, dedup_key)`), `mark_followed_up`, `awaiting_follow_up` and
  `volume_report`.
- `AshOperations.Resources.Delivery` options and functions, asked for by its first host:
  `settle_changes:` layers host changes on `mark_followed_up` so a host's follow-up is that one
  settle path instead of a hand-written action; `subject_required?: true` makes `subject_id`
  mandatory; `recorded?/2` reports whether a `(provider, dedup_key)` is stored. Settling a
  delivery that is no longer `received` is a no-op that returns the stored row. The migration
  defaults for adopting the macro on an existing table are documented.
- `AshOperations.A2ui.Deliveries`: an optional ash_a2ui surface over the delivery resource (table
  with search, facets and range filter, detail, per-provider report, and an optional "Reconcile
  now" row action over a host-named action). ash_a2ui is an optional dependency; the package
  compiles and tests without it (`ASH_OPERATIONS_NO_A2UI=1`).
- `AshOperations.Gettext` and `AshOperations.Surfaces.Labels`: the surface labels as an
  `ash_operations_surfaces` gettext domain, English shipped.
