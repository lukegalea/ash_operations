defmodule AshOperations.Gettext do
  @moduledoc """
  Gettext backend for the text ash_operations writes for a reader. One domain today,
  `ash_operations_surfaces`, holding the operator surface labels (see
  `AshOperations.Surfaces.Labels`). The shipped catalog is English; a host translates by adding
  its own `ash_operations_surfaces.po` under its locale, or through ash_a2ui's metadata domain.
  """
  use Gettext.Backend, otp_app: :ash_operations
end
