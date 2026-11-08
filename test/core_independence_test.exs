defmodule AshOperations.CoreIndependenceTest do
  @moduledoc """
  ash_a2ui is an optional dependency: nothing outside `AshOperations.A2ui` may reference it, so
  the package compiles and works without it (`ASH_OPERATIONS_NO_A2UI=1 mix test` proves it).
  """
  use ExUnit.Case, async: true

  alias AshOperations.Surfaces.Labels

  test "only the A2ui modules mention AshA2ui" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.reject(
        &(&1 == "lib/ash_operations/a2ui.ex" or
            String.starts_with?(&1, "lib/ash_operations/a2ui/"))
      )
      |> Enum.filter(&(File.read!(&1) =~ "AshA2ui"))

    assert offenders == []
  end

  test "the surface labels are available without ash_a2ui" do
    assert Labels.text(:provider) == "Provider"
    assert is_boolean(AshOperations.A2ui.available?())
  end
end
