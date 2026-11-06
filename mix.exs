defmodule AshOperations.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/lukegalea/ash_operations"

  def project do
    [
      app: :ash_operations,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Declare a provider's HTTP operations on an Ash resource: one generic action per " <>
          "operation, a spec pinned at compile time, one retry table and typed errors.",
      package: package(),
      aliases: aliases(),
      docs: &docs/0
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      files:
        ~w(lib documentation mix.exs README.md CHANGELOG.md LICENSE usage-rules.md .formatter.exs),
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        {"README.md", title: "Home"},
        "documentation/tutorials/getting-started.md",
        {"documentation/dsls/DSL-AshOperations.md",
         search_data: Spark.Docs.search_data_for(AshOperations)},
        "usage-rules.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Tutorials: ~r"documentation/tutorials",
        DSLs: ~r"documentation/dsls",
        "About AshOperations": ["usage-rules.md", "CHANGELOG.md"]
      ]
    ]
  end

  defp aliases do
    [
      docs: ["spark.cheat_sheets", "docs", "spark.replace_doc_links"],
      "spark.formatter": "spark.formatter --extensions AshOperations",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshOperations"
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.37"},
      {:spark, "~> 2.7"},
      {:splode, "~> 0.3"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:decimal, "~> 2.0 or ~> 3.0"},
      {:plug, "~> 1.16"},
      {:plug_crypto, "~> 2.0"},
      {:telemetry, "~> 1.0"},
      {:bandit, "~> 1.5", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.8", optional: true},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false}
    ]
  end
end
