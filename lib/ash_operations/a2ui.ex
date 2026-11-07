defmodule AshOperations.A2ui do
  @moduledoc """
  The operator surfaces: ash_a2ui screens over a host's operations resources, so a person can
  see what the providers sent and act on it.

  Each surface is a macro a host binds to its own resource in its web layer. It expands to an
  `AshA2ui.Standalone` module, so the host's domain layer never depends on `ash_a2ui`, which is
  an **optional** dependency of this package: without it the package, the resource macros and
  these modules still compile, and only expanding a surface macro raises.

      defmodule MyAppWeb.A2ui.DeliveriesUI do
        use AshOperations.A2ui.Deliveries,
          resource: MyApp.Ops.Delivery,
          reconcile_action: :reconcile_now
      end

  | Surface | Bound to | Reads | Acts |
  |---|---|---|---|
  | `AshOperations.A2ui.Deliveries` | a `AshOperations.Resources.Delivery` | `:read`, `:volume_report` | the host's `:reconcile_action`, if given |

  Every act is an action on the host's resource under the host's policies; a surface only names
  the reads and actions in its contract and ash_a2ui's verifiers check them when the host
  compiles. Mounting (routes, shell entries) stays the host's.
  """

  @doc "Whether the optional `ash_a2ui` dependency is available in this build."
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(AshA2ui.Standalone)

  @doc false
  @spec ensure_available!(module()) :: :ok
  def ensure_available!(surface) do
    if available?() do
      :ok
    else
      raise CompileError,
        description:
          "#{inspect(surface)} expands to an AshA2ui surface; add " <>
            ~s({:ash_a2ui, github: "lukegalea/ash_a2ui"}) <> " to your dependencies"
    end
  end
end
