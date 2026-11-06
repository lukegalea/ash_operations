defmodule AshOperations.DeclarationTest do
  @moduledoc """
  What the declared-operation core refuses at compile time, and the boundary
  that keeps it promotable to a package.

  Spark reports a verifier failure as a compile diagnostic (fatal under
  `--warnings-as-errors`), so each case compiles a fixture module and asserts on
  the diagnostic it produced.
  """

  use ExUnit.Case, async: true

  @sha "306e2a51a9d8342ef381e377ea9b3b585694a094d8cf2048b9571336e1e2461b"
  @spec_path "test/fixtures/acme_widgets.openapi.json"

  defp compile(section, operations) do
    module = :"Elixir.OperationsDeclarationFixture#{System.unique_integer([:positive])}"

    code = """
    defmodule #{inspect(module)} do
      use Ash.Resource,
        domain: nil,
        validate_domain_inclusion?: false,
        extensions: [AshOperations]

      resource do
        require_primary_key? false
      end

      operations do
        provider :fixture
        transport AshOperations.Test.Transport
        #{section}

        #{operations}
      end
    end
    """

    {_result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          Code.compile_string(code)
        after
          :code.purge(module)
          :code.delete(module)
        end
      end)

    Enum.map(diagnostics, & &1.message)
  end

  defp assert_refused(messages, fragment) do
    assert Enum.any?(messages, &(&1 =~ fragment)),
           "expected a diagnostic containing #{inspect(fragment)}, got: #{inspect(messages)}"
  end

  @documented ~s(documented_at "https://provider.example/docs")

  test "a well-formed declaration compiles clean" do
    assert [] =
             compile(~s(spec "#{@spec_path}"\nspec_sha256 "#{@sha}"), """
             operation :list, :get, "/widgets" do
               param :name_contains, :string, as: "nameContains"
             end

             operation :create, :post, "/widgets" do
               reconcile_with :list
               param :name, :string, in: :body
             end

             operation :remove, :delete, "/widgets/{widget_id}" do
               param :widget_id, :string, in: :path
             end
             """)
  end

  test "a credential is never an argument" do
    for name <- ["api_key", "access_token", "signing_secret", "authorization"] do
      compile("", """
      operation :list, :get, "/x" do
        #{@documented}
        param :#{name}, :string
      end
      """)
      |> assert_refused("names a credential")
    end

    compile("", """
    operation :list, :get, "/x" do
      #{@documented}
      param :innocent, :string, as: "X-Api-Key"
    end
    """)
    |> assert_refused("names a credential")
  end

  test "a non-idempotent operation must decide how it is reconciled" do
    compile("", """
    operation :create, :post, "/x" do
      #{@documented}
    end
    """)
    |> assert_refused("is not idempotent")

    compile("", """
    operation :create, :post, "/x" do
      #{@documented}
      reconcile_with :none
    end
    """)
    |> Enum.reject(&(&1 =~ "spec")) == []
  end

  test "the reconcile read must be an idempotent read" do
    compile("", """
    operation :create, :post, "/x" do
      #{@documented}
      reconcile_with :other
    end

    operation :other, :post, "/y" do
      #{@documented}
      reconcile_with :none
    end
    """)
    |> assert_refused("must be an idempotent read operation")

    compile("", """
    operation :create, :post, "/x" do
      #{@documented}
      reconcile_with :missing
    end
    """)
    |> assert_refused("is not a declared operation")
  end

  test "disclosure needs a gate" do
    compile("", """
    operation :send, :post, "/x" do
      #{@documented}
      reconcile_with :none
      discloses? true
    end
    """)
    |> assert_refused("needs a `disclosure_gate`")
  end

  test "path placeholders and params agree; params go where the encoding allows" do
    compile("", """
    operation :get, :get, "/x/{id}" do
      #{@documented}
    end
    """)
    |> assert_refused("has no `param :id")

    compile("", """
    operation :upload, :post, "/x" do
      #{@documented}
      request :multipart
      reconcile_with :none
      param :name, :string, in: :body
    end
    """)
    |> assert_refused("needs `request :json`")
  end

  test "without a spec every operation cites its documentation" do
    compile("", """
    operation :list, :get, "/x" do
    end
    """)
    |> assert_refused("must cite `documented_at`")
  end

  test "an endpoint the provider does not publish fails compilation" do
    compile(~s(spec "#{@spec_path}"\nspec_sha256 "#{@sha}"), """
    operation :list, :get, "/gadgets" do
    end
    """)
    |> assert_refused("GET /gadgets is not in #{@spec_path}")

    compile(~s(spec "#{@spec_path}"\nspec_sha256 "#{@sha}"), """
    operation :patch_widget, :patch, "/widgets/{widget_id}" do
      reconcile_with :none
      param :widget_id, :string, in: :path
    end
    """)
    |> assert_refused("PATCH /widgets/{widget_id} is not in")
  end

  test "a spec that changed without its pin fails compilation" do
    compile(~s(spec "#{@spec_path}"\nspec_sha256 "#{String.duplicate("0", 64)}"), """
    operation :list, :get, "/widgets" do
    end
    """)
    |> assert_refused("has sha-256 #{@sha}")

    compile(~s(spec "#{@spec_path}"), """
    operation :list, :get, "/widgets" do
    end
    """)
    |> assert_refused("`spec` needs `spec_sha256`")
  end

  describe "the package boundary" do
    @core ["lib/ash_operations.ex" | Path.wildcard("lib/ash_operations/**/*.ex")]

    test "library code never references a test module" do
      {:ok, mods} = :application.get_key(:ash_operations, :modules)

      refs =
        for mod <- mods,
            name = Atom.to_string(mod),
            String.starts_with?(name, "Elixir.AshOperations") and not (name =~ ".Test."),
            {:ok, {_, [atoms: atoms]}} = :beam_lib.chunks(:code.which(mod), [:atoms]),
            {_, atom} <- atoms,
            text = Atom.to_string(atom),
            text =~ "AshOperations.Test.",
            do: {mod, atom}

      assert refs == [], "test modules referenced from library code: #{inspect(refs)}"
    end

    test "the core names no job runner or web framework" do
      offenders =
        for path <- @core,
            File.read!(path) =~ ~r/\b(Oban|Phoenix)\./,
            do: Path.basename(path)

      assert offenders == []
    end

    test "the core holds the only Req call on the operations path" do
      callers =
        for path <- @core,
            File.read!(path) =~ ~r/\bReq\.(request|get|post|put|patch|delete|new)\b/,
            do: Path.basename(path)

      assert callers == ["http.ex"]
    end
  end
end
