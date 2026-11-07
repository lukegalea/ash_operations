defmodule AshOperations.Resources.Delivery.Unsettled do
  @moduledoc """
  Passes while the stored delivery is still `received`. `mark_followed_up` uses it as the
  `where` of every settle change, so a delivery that is already settled is left exactly as it is.
  It reads the stored row, not the changeset, so earlier changes in the same action that set
  `state` do not switch the later ones off.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(%{data: %{state: :received}}, _opts, _context), do: :ok
  def validate(_changeset, _opts, _context), do: {:error, message: "delivery is already settled"}

  @impl true
  def atomic(_changeset, _opts, _context),
    do: {:not_atomic, "reads the stored delivery state, not the changeset"}
end
