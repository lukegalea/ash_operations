defmodule AshOperations.Test.DroppingAdapter do
  @moduledoc "A Plug adapter whose body read raises the way Bandit does when the peer drops."

  def read_req_body(_state, _opts),
    do: raise(Bandit.HTTPError, message: "closed", plug_status: :bad_request)

  defdelegate send_resp(state, status, headers, body), to: Plug.Adapters.Test.Conn
end
