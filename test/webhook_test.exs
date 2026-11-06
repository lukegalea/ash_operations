defmodule AshOperations.WebhookTest do
  @moduledoc "The provider-neutral webhook ingress and its signature helpers."

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test

  alias AshOperations.Test.{DefaultCapProvider, WebhookProvider}
  alias AshOperations.Webhook.{Ingress, Signature}

  @opts Ingress.init(
          providers: %{"test" => WebhookProvider, "plain" => DefaultCapProvider},
          telemetry_prefix: [:test, :webhook]
        )

  defp post(provider, body, headers \\ []) do
    conn = conn(:post, "/#{provider}", body)
    conn = %{conn | path_params: %{"provider" => provider}}
    conn = Enum.reduce(headers, conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
    Ingress.call(conn, @opts)
  end

  defp json(mode), do: ~s({"mode": "#{mode}"})

  test "an unknown provider is 404 and nothing is read" do
    conn = post("unknown", json("x"))
    assert conn.status == 404
    refute_received {:verified, _}
  end

  test "a content-length above the cap is 413 before verify" do
    conn =
      conn(:post, "/test", "{}")
      |> Map.put(:path_params, %{"provider" => "test"})
      |> Plug.Conn.put_req_header("content-length", "5000")
      |> Ingress.call(@opts)

    assert conn.status == 413
    refute_received {:verified, _}
  end

  test "a body above the cap with no content-length is 413" do
    conn = post("test", String.duplicate("a", 2_000))
    assert conn.status == 413
    refute_received {:enqueued, _, _}
  end

  test "an unauthorized verify is 401 and never enqueues" do
    conn = post("test", json("x"), [{"x-test-verify", "unauthorized"}])
    assert conn.status == 401
    refute_received {:enqueued, _, _}
  end

  test "an unconfigured provider is 503" do
    assert post("test", json("x"), [{"x-test-verify", "not_configured"}]).status == 503
  end

  test "verify receives the exact bytes" do
    raw = ~s({ "mode" : "x",  "probe": 1899.10 })
    post("test", raw)
    assert_received {:verified, ^raw}
  end

  test "bad JSON and a non-object are 400" do
    assert post("test", "{nope").status == 400
    assert post("test", "[1]").status == 400
  end

  test "a body read that raises a 408 HTTP error is 408 and still emits telemetry" do
    id = {__MODULE__, make_ref()}
    parent = self()

    :telemetry.attach(
      id,
      [:test, :webhook, :received],
      fn _, _, meta, _ -> send(parent, {:event, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)

    conn = %{conn(:post, "/test", "x") | path_params: %{"provider" => "test"}}
    {_, state} = conn.adapter
    conn = %{conn | adapter: {AshOperations.Test.RaisingAdapter, state}}

    assert Ingress.call(conn, @opts).status == 408
    assert_received {:event, %{status: 408, outcome: :timeout}}
  end

  test "a dedup key error is 400" do
    assert post("test", json("x"), [{"x-test-key", "none"}]).status == 400
  end

  test "enqueued, duplicate and ignored are 204 with an empty body" do
    for mode <- ~w(enqueued duplicate ignored) do
      conn = post("test", json(mode))
      assert conn.status == 204
      assert conn.resp_body == ""
    end
  end

  test "reject is 400 and error is 503" do
    assert post("test", json("reject")).status == 400
    assert post("test", json("error")).status == 503
  end

  test "a raising provider is 503 and its message is not logged" do
    log = capture_log(fn -> assert post("test", json("raise")).status == 503 end)
    refute log =~ "marker-secret-in-message"
  end

  test "the default cap applies without max_body_bytes/0" do
    assert post("plain", json("x")).status == 204
    assert post("plain", String.duplicate("a", 70_000)).status == 413
  end

  describe "telemetry" do
    setup do
      id = "webhook-test-#{System.unique_integer([:positive])}"
      me = self()

      :telemetry.attach(
        id,
        [:test, :webhook, :received],
        fn _e, m, meta, _ -> send(me, {:telemetry, m, meta}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)
    end

    test "one event per request with only structural metadata" do
      post("test", json("enqueued"))
      assert_receive {:telemetry, %{bytes: _}, meta}
      assert Map.keys(meta) -- [:provider, :outcome, :status, :exception] == []
      assert meta.outcome == :enqueued
      refute_receive {:telemetry, _, _}, 20
    end

    test "an unknown provider reports :unknown" do
      post("unknown", "{}")
      assert_receive {:telemetry, _, %{provider: :unknown, status: 404}}
    end
  end

  describe "Signature" do
    test "RFC 4231 case 2" do
      assert Signature.hmac_sha256_hex("Jefe", "what do ya want for nothing?") ==
               "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
    end

    test "valid_hex?" do
      sig = Signature.hmac_sha256_hex("b", "m")
      assert Signature.valid_hex?(sig, ["a", "b"], "m")
      assert Signature.valid_hex?(String.upcase(sig), ["a", "b"], "m")
      refute Signature.valid_hex?(sig, [], "m")
      refute Signature.valid_hex?(String.slice(sig, 0, 63), ["b"], "m")
      refute Signature.valid_hex?(sig, ["a"], "m")
    end

    test "fresh?" do
      assert Signature.fresh?("1000", 1300, 300)
      assert Signature.fresh?("1000", 700, 300)
      refute Signature.fresh?("1000", 1301, 300)
      refute Signature.fresh?("1000", 699, 300)
      refute Signature.fresh?("12a", 12, 300)
      refute Signature.fresh?("", 0, 300)
      refute Signature.fresh?("1234567890123", 1_234_567_890_123, 300)
    end
  end
end
