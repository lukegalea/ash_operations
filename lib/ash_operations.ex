defmodule AshOperations do
  @moduledoc """
  The declared-operation core: declare what a provider's
  API offers, get one policy-gated generic Ash action per operation, and let one
  transport module hold the only HTTP client for that provider.

      operations do
        provider :acme
        transport MyApp.Provider.Proxy
        spec "priv/vendor/acme/api-reference.json"
        spec_sha256 "dbbbdff8…"
        disclosure_gate MyApp.Extraction.Gate

        operation :upload_file, :post, "/files/upload" do
          request :multipart
          reconcile_with :list_files
          discloses? true
          param :file, :map, in: :part, allow_nil?: false
        end

        operation :list_files, :get, "/files" do
          param :name_contains, :string, as: "nameContains"
        end
      end

  Every operation becomes `action <name>, :map` plus a code interface of the
  same name. The action returns the provider's decoded body.

  ## What the core guarantees

    * **One HTTP client per provider.** The `transport` is the only module that
      speaks HTTP for the provider. Operations never carry a
      credential: `Verifiers.Declaration` refuses a param shaped like one.
    * **The spec is pinned.** With `spec` set, every operation's method and path
      must exist in the vendored OpenAPI document, whose sha-256 must equal
      `spec_sha256` (`Verifiers.SpecResolves`). Editing the file without the pin,
      or declaring an endpoint the provider does not publish, fails compilation.
      A provider without a published spec declares `documented_at` per operation
      instead.
    * **Ambiguity is explicit.** A non-idempotent operation that times out or
      gets a 5xx is never re-sent; it fails with reason `:ambiguous`. Every
      non-idempotent operation must name the read it is reconciled through
      (`reconcile_with`) or opt out with `reconcile_with :none`.
      `AshOperations.Reconcile` runs that read.
    * **Disclosure is gated.** An operation marked `discloses? true` takes a
      required `disclosure_ref` argument and calls the section's
      `disclosure_gate` before any byte leaves; a refusal sends nothing.
    * **Effects are declared.** `effect` (`:read` or `:write`, defaulted from the
      method) is carried into telemetry.

  The core names no host module: the host supplies the transport, the gate and
  the resource's policies. That keeps it promotable to a package.
  """

  alias AshOperations.{Operation, Param}

  @param %Spark.Dsl.Entity{
    name: :param,
    describe: "One input to the operation: an action argument and one request field.",
    target: Param,
    args: [:name, :type],
    identifier: :name,
    schema: [
      name: [type: :atom, required: true, doc: "The action argument name (snake_case)."],
      type: [type: :any, required: true, doc: "The Ash type of the argument."],
      as: [type: :string, doc: "The provider's own name for the field. Defaults to `name`."],
      in: [
        type: {:one_of, [:query, :path, :body, :part]},
        default: :query,
        doc: """
        Where the value goes: a query parameter, a `{placeholder}` path segment,
        a top-level JSON body field, or a multipart part. A `:part` value is a
        string, or `%{content: binary, filename: String.t(), content_type: String.t()}`
        for a file.
        """
      ],
      allow_nil?: [type: :boolean, default: true, doc: "Whether the argument may be omitted."],
      default: [type: :any, doc: "Default argument value."],
      constraints: [type: :keyword_list, default: [], doc: "Ash type constraints."],
      description: [type: :string, doc: "Argument description."],
      sensitive?: [
        type: :boolean,
        default: false,
        doc: "Marks the argument sensitive, so Ash redacts it from inspect output."
      ]
    ]
  }

  @operation %Spark.Dsl.Entity{
    name: :operation,
    describe: "A provider operation; becomes one generic action of the same name.",
    target: Operation,
    args: [:name, :method, :path],
    identifier: :name,
    transform: {Operation, :transform, []},
    entities: [params: [@param]],
    schema: [
      name: [type: :atom, required: true, doc: "The generated action's name."],
      method: [
        type: {:one_of, [:get, :post, :put, :patch, :delete]},
        required: true,
        doc: "The HTTP method."
      ],
      path: [
        type: :string,
        required: true,
        doc: "Path relative to the transport's base URL; `{param}` placeholders allowed."
      ],
      description: [type: :string, doc: "The generated action's description."],
      request: [
        type: {:one_of, [:json, :multipart, :none]},
        doc: "Request body encoding. Defaults to `:json` for post, put and patch, else `:none`."
      ],
      response: [
        type: {:one_of, [:json, :binary, :none]},
        default: :json,
        doc: """
        `:json` decodes with floats as `Decimal`. `:binary`
        returns `%{"content" => binary, "content_type" => type}`. `:none`
        returns `%{}`.
        """
      ],
      timeout: [
        type: :pos_integer,
        default: 15_000,
        doc: "Receive timeout in milliseconds for one attempt."
      ],
      idempotent?: [
        type: :boolean,
        doc: """
        Whether re-sending is safe after a timeout or 5xx. Defaults to true for
        get, put and delete, false for post and patch.
        """
      ],
      effect: [
        type: {:one_of, [:read, :write]},
        doc: "What the call does at the provider. Defaults to `:read` for get, else `:write`."
      ],
      reconcile_with: [
        type: :atom,
        doc: """
        The idempotent read operation that finds what an ambiguous call may have
        created, or `:none` to opt out. Required on non-idempotent operations.
        """
      ],
      discloses?: [
        type: :boolean,
        default: false,
        doc: """
        Whether the call sends data the host classifies (documents, personal
        data). Adds a required `disclosure_ref` argument and runs the section's
        `disclosure_gate` before anything is sent.
        """
      ],
      documented_at: [
        type: :string,
        doc: """
        For a provider with no published machine-readable spec: the URL of the
        documentation this operation was declared from. Ignored when the section
        has a `spec`.
        """
      ]
    ]
  }

  @operations %Spark.Dsl.Section{
    name: :operations,
    describe: "Declared provider operations, one generic action each.",
    schema: [
      provider: [
        type: :atom,
        required: true,
        doc: "The provider's name, carried into errors and telemetry."
      ],
      transport: [
        type: {:behaviour, AshOperations.Transport},
        required: true,
        doc: "The module that performs requests: the provider's only HTTP client."
      ],
      spec: [
        type: :string,
        doc: "Path, relative to the project root, of the vendored OpenAPI 3.x JSON document."
      ],
      spec_sha256: [
        type: :string,
        doc: "Lowercase hex sha-256 of the `spec` file. Required with `spec`."
      ],
      disclosure_gate: [
        type: {:behaviour, AshOperations.DisclosureGate},
        doc: "Consulted before every `discloses? true` operation sends anything."
      ],
      telemetry_prefix: [
        type: {:list, :atom},
        default: [:operations, :request],
        doc: "Prefix of the `:start`, `:stop` and `:exception` span events."
      ]
    ],
    entities: [@operation]
  }

  use Spark.Dsl.Extension,
    sections: [@operations],
    transformers: [AshOperations.Transformers.AddOperationActions],
    verifiers: [
      AshOperations.Verifiers.Declaration,
      AshOperations.Verifiers.SpecResolves
    ]
end
