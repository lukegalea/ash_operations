defmodule Mix.Tasks.AshOperations.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs AshOperations: formatter entry and a commented provider example"
  end

  def example do
    "mix igniter.install ash_operations"
  end

  def long_doc do
    """
    #{short_doc()}

    Adds `:ash_operations` to `import_deps` in `.formatter.exs`, so the `operations` DSL
    formats without parentheses, and creates `lib/<app>/operations/example_provider.ex`, a
    module holding a commented example of a transport and a resource for a fictional provider.
    Delete the file once you have written your own.

    ## Example

    ```bash
    #{example()}
    ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshOperations.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()
    use Igniter.Mix.Task

    alias Igniter.Project.Formatter
    alias Igniter.Project.Module, as: ProjectModule

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash,
        adds_deps: [],
        installs: [],
        example: __MODULE__.Docs.example(),
        only: nil,
        positional: [],
        composes: [],
        schema: [],
        defaults: [],
        aliases: [],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      module = ProjectModule.module_name(igniter, "Operations.ExampleProvider")

      igniter
      |> Formatter.import_dep(:ash_operations)
      |> ProjectModule.create_module(module, example_body(), location: :source_folder)
    end

    defp example_body do
      """
      @moduledoc \"\"\"
      A commented example of a provider's operations. Delete this module once you have
      declared your own.

      The transport holds the only HTTP client for the provider and reads secrets at call time:

          defmodule MyApp.Acme.Api do
            use AshOperations.Http

            @impl true
            def config do
              case System.get_env("ACME_API_KEY") do
                key when key in [nil, ""] -> {:error, :not_configured}
                key -> {:ok, %{base_url: "https://api.acme.example", auth: {:bearer, key}}}
              end
            end
          end

      The resource declares one generic action per operation:

          defmodule MyApp.Acme.Widgets do
            use Ash.Resource, domain: MyApp.Acme, extensions: [AshOperations]

            operations do
              provider :acme
              transport MyApp.Acme.Api
              spec "priv/vendor/acme/openapi.json"
              spec_sha256 "<sha-256 of the vendored spec>"

              operation :list_widgets, :get, "/widgets"

              operation :create_widget, :post, "/widgets" do
                reconcile_with :list_widgets
                param :name, :string, in: :body, allow_nil?: false
              end
            end

            resource do
              require_primary_key? false
            end
          end
      \"\"\"
      """
    end
  end
end
