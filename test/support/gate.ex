defmodule AshOperations.Test.Gate do
  @moduledoc "Refuses `disclosure_ref: \"refuse\"`; reports every call as `{:gate, subject}`."
  @behaviour AshOperations.DisclosureGate

  @impl true
  def authorize(subject, _context) do
    send(self(), {:gate, subject})
    if subject.disclosure_ref == "refuse", do: {:error, "test_refusal"}, else: :ok
  end
end
