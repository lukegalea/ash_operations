# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's private vulnerability reporting:
<https://github.com/lukegalea/ash_operations/security/advisories/new>. Do not open a public
issue or pull request for a suspected vulnerability. You will get an acknowledgement, and we
will agree a disclosure date with you once the fix is ready.

## Supported versions

Only the latest release tag and `main` receive fixes.

## Scope

The areas where a flaw is most likely to matter:

- **Webhook signature verification.** The ingress plug reads the raw request body and verifies
  the signature before anything is enqueued. Bypasses, timing leaks and replay handling are in
  scope.
- **Secret handling.** Credentials are read at call time by the transport and are never action
  arguments. Anything that lets a secret reach compile-time state, an action argument, an error
  or telemetry is in scope.
- **Request logging.** Errors carry no response bodies, and telemetry carries no paths, queries,
  bodies or headers. Any leak of those into logs, errors or telemetry is in scope.

Vulnerabilities in the HTTP server, in a provider's API or in your own transport and policies
are out of scope.
