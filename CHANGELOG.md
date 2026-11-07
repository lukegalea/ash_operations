# Changelog

## Unreleased

- The webhook ingress answers 408 when the body read times out. Bandit raises with an atom
  `plug_status` (`:request_timeout`); the status is now resolved with `Plug.Exception.status/1`.
- The minimum supported Elixir is now 1.20 (was 1.18).
- First extraction: the `operations` DSL, `AshOperations.Http` transport over `Req`, the shared
  retry table, typed errors, spec pinning, reconciliation, the disclosure gate and the webhook
  ingress plug.
