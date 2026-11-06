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
      docs: docs()
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE usage-rules.md .formatter.exs),
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md", "CHANGELOG.md", "usage-rules.md"]]
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
