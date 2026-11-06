# AshOperations

[![CI](https://github.com/lukegalea/ash_operations/actions/workflows/ci.yml/badge.svg)](https://github.com/lukegalea/ash_operations/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/lukegalea/ash_operations/blob/main/LICENSE)

Declare the HTTP operations of a provider's API on an Ash resource. Each operation becomes one
generic Ash action and one code interface function, so every outbound call goes through your
policies, your actor and your tenant like any other action.

What the library gives you:

- **One HTTP client per provider.** A transport module holds the only `Req` call. Secrets are read
  at call time, never at compile time, and are never action arguments.
- **A pinned spec.** Point at a vendored OpenAPI 3.x JSON file and its sha-256. A declared method
  and path the provider does not publish, or an edited spec without a new pin, fails compilation.
- **One retry table.** 429 honours `Retry-After`; a non-idempotent call that times out or gets a
  5xx is never re-sent and fails `:ambiguous`; a wait over the cap is reported, not slept.
- **Ambiguity decided at declaration time.** A non-idempotent operation names the read that finds
  what it may have created (`reconcile_with`), or opts out with `reconcile_with :none`.
- **A disclosure gate.** Operations marked `discloses? true` ask your gate before a byte is sent.
- **Typed errors without bodies**, and structural telemetry (no paths, queries, bodies, headers).
- **A webhook ingress plug** that reads the raw bytes, verifies, de-duplicates and enqueues.

## Example

```elixir
defmodule Acme.Api do
  use AshOperations.Http

  @impl true
  def config do
    case System.get_env("ACME_API_KEY") do
      key when key in [nil, ""] -> {:error, :not_configured}
      key -> {:ok, %{base_url: "https://api.acme.example", auth: {:bearer, key}}}
    end
  end
end

defmodule Acme.Widgets do
  use Ash.Resource, domain: Acme.Domain, extensions: [AshOperations]

  operations do
    provider :acme
    transport Acme.Api
    spec "priv/vendor/acme/openapi.json"
    spec_sha256 "306e2a51a9d8342ef381e377ea9b3b585694a094d8cf2048b9571336e1e2461b"

    operation :list_widgets, :get, "/widgets" do
      param :name_contains, :string, as: "nameContains"
    end

    operation :create_widget, :post, "/widgets" do
      reconcile_with :list_widgets
      param :name, :string, in: :body, allow_nil?: false
    end
  end

  resource do
    require_primary_key? false
  end
end

{:ok, body} = Acme.Widgets.create_widget(%{name: "sprocket"}, actor: actor)

case AshOperations.Error.reason(error) do
  :ambiguous -> AshOperations.Reconcile.find(Acme.Widgets, :create_widget, %{name_contains: "sprocket"}, &(&1["data"]))
  :rate_limited -> :snooze
  _ -> :fail
end
```

To format the DSL without parentheses, import it in `.formatter.exs`:
`import_deps: [:ash_operations]`.

## Requirements

Elixir 1.20 or later, on OTP 27 or 28.

## Installation

AshOperations is not published to Hex. Pin it by git tag:

```elixir
def deps do
  [{:ash_operations, github: "lukegalea/ash_operations", tag: "v0.1.0"}]
end
```

With [Igniter](https://hexdocs.pm/igniter) in your project, `mix igniter.install ash_operations`
adds the formatter entry and a commented provider example. See `CHANGELOG.md`.

## License

MIT. See [LICENSE](https://github.com/lukegalea/ash_operations/blob/main/LICENSE).
