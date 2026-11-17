defmodule AshOperations.OutboundContextTest do
  @moduledoc """
  The call reaches the transport: `meta.call` carries the action's actor, tenant and
  `in: :context` params; `config/1` chooses the destination per call; `sign/3` signs
  the exact bytes sent; and a transport can refuse to follow redirects. Transports that
  define only `config/0` keep working unchanged (`AshOperationsTest`).
  """

  use ExUnit.Case, async: true

  alias AshOperations.{Error, Info}
  alias AshOperations.Test.{Hooks, HooksTransport}

  @stub HooksTransport

  defp ok(conn), do: Plug.Conn.send_resp(conn, 204, "")

  defp json(conn, raw) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, raw)
  end

  test "a transport that defines neither config/0 nor config/1 does not compile" do
    assert_raise CompileError, ~r/defines neither config\/0 nor config\/1/, fn ->
      Code.compile_string("""
      defmodule AshOperations.OutboundContextTest.NoConfig do
        use AshOperations.Http
      end
      """)
    end
  end

  test "a config/1 refusal fails the call before anything is sent" do
    Req.Test.stub(@stub, fn _conn -> flunk("nothing may be sent") end)

    assert {:error, error} =
             Hooks.deliver(%{destination: "unknown", event: "e1"}, authorize?: false)

    assert %Error{reason: :not_configured, provider: :hooks, operation: :deliver} =
             Error.unwrap(error)

    assert {:error, error} =
             Hooks.deliver(%{destination: "refused", event: "e1"}, authorize?: false)

    assert %Error{reason: :disclosure_refused, provider_code: "destination_refused"} =
             Error.unwrap(error)
  end

  test "a 3xx is not followed" do
    Req.Test.stub(@stub, fn
      %{host: "a.hooks.test"} = conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "http://elsewhere.hooks.test/")
        |> Plug.Conn.send_resp(307, "")

      _conn ->
        flunk("the redirect was followed")
    end)

    assert {:error, error} = Hooks.deliver(%{destination: "a", event: "e1"}, authorize?: false)
    assert %Error{reason: :bad_request, status: 307} = Error.unwrap(error)
  end

  test "config/1 receives the call's actor and tenant" do
    Req.Test.stub(@stub, &ok/1)
    actor = %{id: "actor-1"}

    assert {:ok, %{}} =
             Hooks.deliver(%{destination: "a", event: "e1"},
               actor: actor,
               tenant: "tenant-1",
               authorize?: false
             )

    assert_received {:config_call, call}
    assert call.actor == actor
    assert call.tenant == "tenant-1"
    assert call.context_params == %{destination: "a"}
  end

  test "a :context param never reaches the wire" do
    Req.Test.stub(@stub, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      # The destination chose the host and is nowhere else on the request.
      assert conn.host == "secret-place.hooks.test"
      assert conn.query_params == %{}
      assert Jason.decode!(raw) == %{"event" => "e1"}
      refute raw =~ "secret-place"
      refute Enum.any?(conn.req_headers, fn {_k, v} -> v =~ "secret-place" end)
      ok(conn)
    end)

    assert {:ok, %{}} =
             Hooks.deliver(%{destination: "secret-place", event: "e1"}, authorize?: false)

    Req.Test.stub(@stub, fn conn ->
      assert conn.query_string == ""
      json(conn, "{}")
    end)

    assert {:ok, %{}} = Hooks.peek(%{destination: "secret-place"}, authorize?: false)

    # It is an argument of the action, so it is cast and required like any other.
    action = Ash.Resource.Info.action(Hooks, :deliver)
    assert %{allow_nil?: false} = Enum.find(action.arguments, &(&1.name == :destination))

    assert %{in: :context} =
             Enum.find(Info.operation(Hooks, :deliver).params, &(&1.name == :destination))
  end

  test "sign/3 headers cover the exact bytes sent" do
    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      [signature] = Plug.Conn.get_req_header(conn, "x-signature")

      expected =
        :crypto.mac(:hmac, :sha256, HooksTransport.secret(), raw) |> Base.encode64()

      assert signature == expected
      assert ["application/json"] = Plug.Conn.get_req_header(conn, "content-type")
      assert ["application/json"] = Plug.Conn.get_req_header(conn, "accept")
      ok(conn)
    end)

    data = %{"amount" => Decimal.new("10.50"), "names" => ["a", "é"], "nested" => %{"k" => nil}}

    assert {:ok, %{}} =
             Hooks.deliver(%{destination: "a", event: "e1", data: data}, authorize?: false)

    assert_received {:signed, bytes}
    assert Jason.decode!(bytes)["data"]["names"] == ["a", "é"]
  end

  test "a request without a body signs the empty string" do
    Req.Test.stub(@stub, fn conn ->
      assert [_signature] = Plug.Conn.get_req_header(conn, "x-signature")
      json(conn, "{}")
    end)

    assert {:ok, %{}} = Hooks.peek(%{destination: "a"}, authorize?: false)
    assert_received {:signed, ""}
  end

  test "retries resend the same signed bytes" do
    counter = :counters.new(1, [])

    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      :counters.add(counter, 1, 1)
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:attempt, raw, Plug.Conn.get_req_header(conn, "x-signature")})

      if :counters.get(counter, 1) == 1,
        do: Plug.Conn.send_resp(conn, 503, ""),
        else: ok(conn)
    end)

    assert {:ok, %{}} = Hooks.deliver(%{destination: "a", event: "e1"}, authorize?: false)
    assert :counters.get(counter, 1) == 2

    assert_received {:attempt, raw, [signature]}
    assert_received {:attempt, ^raw, [^signature]}
    assert_received {:signed, ^raw}
    refute_received {:signed, _}
  end
end
