# Getting started

This guide declares two operations of a fictional provider, "Acme", on an Ash resource and calls
them. For every option, see the [DSL reference](dsl-ashoperations.html).

## 1. Install

```elixir
def deps do
  [{:ash_operations, github: "lukegalea/ash_operations", tag: "v0.1.0"}]
end
```

Add the DSL to your formatter so it formats without parentheses:

```elixir
# .formatter.exs
[import_deps: [:ash, :ash_operations]]
```

With Igniter installed, `mix igniter.install ash_operations` does this and adds a commented
provider skeleton.

## 2. Write the transport

A transport module holds the only HTTP client for the provider. Secrets are read at call time:

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
```

## 3. Pin the spec

Vendor the provider's OpenAPI 3.x JSON file into your repository and compute its hash:

```sh
shasum -a 256 priv/vendor/acme/openapi.json
```

A declared method and path that the document does not publish fails compilation, and so does an
edited file whose hash was not updated.

## 4. Declare operations

```elixir
defmodule Acme.Widgets do
  use Ash.Resource, domain: Acme.Domain, extensions: [AshOperations]

  operations do
    provider :acme
    transport Acme.Api
    spec "priv/vendor/acme/openapi.json"
    spec_sha256 "<the hash from step 3>"

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
```

A `POST` is not idempotent, so it must name the read that finds what it may have created
(`reconcile_with`) or opt out with `reconcile_with :none`.

## 5. Call them

```elixir
{:ok, body} = Acme.Widgets.create_widget(%{name: "sprocket"}, actor: actor)
```

Calls go through the resource's policies, your actor and your tenant. Failures are typed; read the
reason with `AshOperations.Error.reason/1`:

```elixir
case AshOperations.Error.reason(error) do
  :ambiguous ->
    AshOperations.Reconcile.find(Acme.Widgets, :create_widget, %{name_contains: "sprocket"}, & &1["data"])

  :rate_limited -> :snooze
  _ -> :fail
end
```

An `:ambiguous` failure means the request may have reached the provider; it is never re-sent.

## 6. A destination chosen per call

Some providers are not one base URL with one credential: an outbound webhook, say, goes to
whichever URL a customer registered, signed with that customer's secret. Give the operation an
`in: :context` param to name the record that holds them, and implement `config/1` instead of
`config/0`. A `:context` param is cast and required like any argument, and never becomes a request
field:

```elixir
operation :deliver, :post, "/" do
  idempotent? true
  response :none
  documented_at "https://example.test/webhooks"
  param :endpoint_id, :uuid, in: :context, allow_nil?: false
  param :type, :string, in: :body, allow_nil?: false
end
```

`config/1` receives the operation's metadata; `meta.call` holds the action's `actor`, its `tenant`
and the `context_params`. Return `redirect: false` when you send to an address you vetted
yourself, so a 3xx cannot take the body somewhere else. To sign, implement `sign/3`: it receives the
exact bytes that will be sent and returns headers.

```elixir
defmodule MyApp.Webhooks.Transport do
  use AshOperations.Http

  @impl true
  def config(%{call: %{tenant: tenant, context_params: %{endpoint_id: id}}}) do
    case MyApp.Webhooks.endpoint(tenant, id) do
      {:ok, endpoint} -> {:ok, %{base_url: endpoint.url, redirect: false, secret: endpoint.secret}}
      :error -> {:error, {:disclosure_refused, "unknown_endpoint"}}
    end
  end

  @impl true
  def sign(body, _meta, %{secret: secret}) do
    [{"x-signature", :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode64()}]
  end
end
```

`{:error, {reason, code}}` fails the call before anything is sent, with `code` as the error's
`provider_code`.
