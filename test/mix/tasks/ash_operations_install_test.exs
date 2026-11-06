defmodule Mix.Tasks.AshOperations.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  test "imports the formatter dependency" do
    test_project()
    |> Igniter.compose_task("ash_operations.install", [])
    |> assert_has_patch(".formatter.exs", """
    + |  import_deps: [:ash_operations]
    """)
  end

  test "creates a commented example provider" do
    test_project()
    |> Igniter.compose_task("ash_operations.install", [])
    |> assert_creates("lib/test/operations/example_provider.ex")
  end

  test "is idempotent" do
    test_project()
    |> Igniter.compose_task("ash_operations.install", [])
    |> apply_igniter!()
    |> Igniter.compose_task("ash_operations.install", [])
    |> assert_unchanged()
  end
end
