defmodule AshOperations.Test.Domain do
  @moduledoc "Test-only domain for the declared-operation core's synthetic provider."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshOperations.Test.Widgets
  end
end
