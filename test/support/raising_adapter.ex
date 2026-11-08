defmodule AshOperations.Test.RaisingAdapter do
  @moduledoc "A Plug adapter whose body read raises the way Bandit does on a read timeout."

  def read_req_body(_state, _opts),
    do: raise(Bandit.HTTPError, message: "timeout", plug_status: :request_timeout)

  defdelegate send_resp(state, status, headers, body), to: Plug.Adapters.Test.Conn
end
