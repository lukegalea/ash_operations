defmodule AshOperationsTest do
  @moduledoc """
  The declared-operation core: declaration → generic action → shared retry
  table → transport, against a synthetic provider (`Test.Operations.Widgets`).

  No network: every request is answered by a `Req.Test` stub owned by the test
  process, and every payload is synthetic.
  """

  use ExUnit.Case, async: true

  alias AshOperations.{Error, Info, Reconcile, Retry}
  alias AshOperations.Test.{Transport, Widgets}

  @stub Transport

  defp json(conn, status, raw) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, raw)
  end

  defp counting_stub(fun) do
    counter = :counters.new(1, [])

    Req.Test.stub(@stub, fn conn ->
      :counters.add(counter, 1, 1)
      fun.(conn, :counters.get(counter, 1))
    end)

    counter
  end

  defp calls(counter), do: :counters.get(counter, 1)

  describe "generated actions" do
    test "one generic action and code interface per operation" do
      names = Widgets |> Info.operations() |> Enum.map(& &1.name)

      for name <- names do
        assert %Ash.Resource.Actions.Action{type: :action} =
                 Ash.Resource.Info.action(Widgets, name)

        assert function_exported?(Widgets, name, 2)
      end
    end

    test "method-dependent defaults are resolved on the entity" do
      assert %{idempotent?: true, effect: :read, request: :none} =
               Info.operation(Widgets, :list_widgets)

      assert %{idempotent?: false, effect: :write, request: :json} =
               Info.operation(Widgets, :create_widget)

      assert %{idempotent?: true, effect: :write} = Info.operation(Widgets, :delete_widget)
    end

    test "discloses? adds a required disclosure_ref argument" do
      action = Ash.Resource.Info.action(Widgets, :create_widget)
      assert %{allow_nil?: false} = Enum.find(action.arguments, &(&1.name == :disclosure_ref))

      refute Enum.any?(
               Ash.Resource.Info.action(Widgets, :list_widgets).arguments,
               &(&1.name == :disclosure_ref)
             )
    end
  end

  describe "requests" do
    test "query params use wire names; JSON numbers decode to Decimal" do
      Req.Test.stub(@stub, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/widgets"
        assert conn.query_params == %{"nameContains" => "ks-1", "maxPageSize" => "5"}
        assert ["Bearer synthetic-test-token"] = Plug.Conn.get_req_header(conn, "authorization")
        assert ["2026-01-01"] = Plug.Conn.get_req_header(conn, "x-widgets-version")
        json(conn, 200, ~s({"data":[{"id":"w1","price":1899.10,"qty":980}]}))
      end)

      assert {:ok, %{"data" => [widget]}} =
               Widgets.list_widgets(%{name_contains: "ks-1", page_size: 5}, authorize?: false)

      assert widget["price"] == Decimal.new("1899.10")
      assert widget["qty"] == 980
    end

    test "a path argument is exactly one encoded segment" do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/widgets/a%2F..%2Fb"
        json(conn, 200, ~s({"id":"x"}))
      end)

      assert {:ok, %{"id" => "x"}} = Widgets.get_widget(%{widget_id: "a/../b"}, authorize?: false)
      assert {:error, error} = Widgets.get_widget(%{widget_id: ".."}, authorize?: false)
      assert Error.reason(error) == :bad_request
    end

    test "body params become one JSON object; decimals stay exact" do
      Req.Test.stub(@stub, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(raw) == %{"name" => "w", "price" => 0.1, "settings" => %{"a" => 1}}
        assert raw =~ ~s("price":0.1)
        json(conn, 200, ~s({"id":"w2"}))
      end)

      assert {:ok, %{"id" => "w2"}} =
               Widgets.create_widget(
                 %{name: "w", price: Decimal.new("0.1"), settings: %{a: 1}, disclosure_ref: "ok"},
                 authorize?: false
               )
    end

    test "multipart parts carry the file name, type and bytes" do
      Req.Test.stub(@stub, fn conn ->
        assert [content_type] = Plug.Conn.get_req_header(conn, "content-type")
        assert content_type =~ "multipart/form-data"
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        assert raw =~ ~s(name="file"; filename="ks-123.pdf")
        assert raw =~ "content-type: application/pdf"
        assert raw =~ "%PDF-synthetic"
        assert raw =~ ~s(name="password")
        json(conn, 200, ~s({"id":"file_1"}))
      end)

      file = %{content: "%PDF-synthetic", filename: "ks-123.pdf", content_type: "application/pdf"}

      assert {:ok, %{"id" => "file_1"}} =
               Widgets.upload_widget(%{file: file, password: "pdf-pass"}, authorize?: false)
    end

    test "binary and empty responses" do
      Req.Test.stub(@stub, fn
        %{method: "GET"} = conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/pdf")
          |> Plug.Conn.send_resp(200, "%PDF")

        %{method: "DELETE"} = conn ->
          Plug.Conn.send_resp(conn, 204, "")
      end)

      assert {:ok, %{"content" => "%PDF", "content_type" => "application/pdf" <> _}} =
               Widgets.get_widget_content(%{widget_id: "w1"}, authorize?: false)

      assert {:ok, %{}} = Widgets.delete_widget(%{widget_id: "w1"}, authorize?: false)
    end
  end

  describe "the retry table" do
    test "429 honours Retry-After, then succeeds" do
      counter =
        counting_stub(fn
          conn, 1 ->
            conn
            |> Plug.Conn.put_resp_header("retry-after", "2")
            |> json(429, ~s({"code":"RATE_LIMIT_EXCEEDED"}))

          conn, _ ->
            json(conn, 200, ~s({"data":[]}))
        end)

      assert {:ok, _} = Widgets.list_widgets(%{}, authorize?: false)
      assert_received {:slept, 2000}
      assert calls(counter) == 2
    end

    test "a 429 wait longer than the cap is not slept; it surfaces for a job to snooze" do
      counting_stub(fn conn, _ ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "600")
        |> json(429, ~s({"code":"RATE_LIMIT_EXCEEDED"}))
      end)

      assert {:error, error} = Widgets.list_widgets(%{}, authorize?: false)
      assert %Error{reason: :rate_limited, retry_after_ms: 600_000} = Error.unwrap(error)
      refute_received {:slept, _}
    end

    test "an idempotent 5xx is retried" do
      counter =
        counting_stub(fn
          conn, n when n < 3 -> json(conn, 503, ~s({"code":"UNAVAILABLE"}))
          conn, _ -> json(conn, 200, ~s({"id":"w1"}))
        end)

      assert {:ok, %{"id" => "w1"}} = Widgets.get_widget(%{widget_id: "w1"}, authorize?: false)
      assert calls(counter) == 3
    end

    test "a non-idempotent 5xx is ambiguous and never re-sent" do
      counter =
        counting_stub(fn conn, _ ->
          json(conn, 500, ~s({"code":"INTERNAL_ERROR","requestId":"req_1"}))
        end)

      assert {:error, error} =
               Widgets.create_widget(%{name: "w", disclosure_ref: "ok"}, authorize?: false)

      assert %Error{
               reason: :ambiguous,
               status: 500,
               provider_code: "INTERNAL_ERROR",
               request_id: "req_1"
             } =
               Error.unwrap(error)

      assert calls(counter) == 1
    end

    test "a non-idempotent timeout is ambiguous and never re-sent" do
      counter = counting_stub(fn conn, _ -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, error} =
               Widgets.create_widget(%{name: "w", disclosure_ref: "ok"}, authorize?: false)

      assert Error.reason(error) == :ambiguous
      assert calls(counter) == 1
    end

    test "a request that provably never left is retried even when not idempotent" do
      counter =
        counting_stub(fn
          conn, 1 -> Req.Test.transport_error(conn, :econnrefused)
          conn, _ -> json(conn, 200, ~s({"id":"w3"}))
        end)

      assert {:ok, %{"id" => "w3"}} =
               Widgets.create_widget(%{name: "w", disclosure_ref: "ok"}, authorize?: false)

      assert calls(counter) == 2
    end

    test "an idempotent timeout is retried, then reported as :timeout" do
      counter = counting_stub(fn conn, _ -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, error} = Widgets.get_widget(%{widget_id: "w1"}, authorize?: false)
      assert Error.reason(error) == :timeout
      assert calls(counter) == 3
    end

    test "4xx are classified, with the provider's code and request id but no message" do
      counting_stub(fn conn, _ ->
        json(
          conn,
          404,
          ~s({"code":"NOT_FOUND","message":"Resource w9 secret-ish detail","requestId":"apireq_9"})
        )
      end)

      assert {:error, error} = Widgets.get_widget(%{widget_id: "w9"}, authorize?: false)

      assert %Error{
               reason: :not_found,
               status: 404,
               provider_code: "NOT_FOUND",
               request_id: "apireq_9"
             } =
               e = Error.unwrap(error)

      refute Exception.message(e) =~ "secret-ish"
    end

    test "an unconfigured transport sends nothing" do
      Process.put(:operations_test_unconfigured, true)
      counter = counting_stub(fn conn, _ -> json(conn, 200, "{}") end)

      assert {:error, error} = Widgets.list_widgets(%{}, authorize?: false)
      assert Error.reason(error) == :not_configured
      assert calls(counter) == 0
    end

    test "Retry.decide covers the table" do
      base = [max_attempts: 3, max_delay_ms: 10_000, base_backoff_ms: 100, retry_after_ms: nil]

      assert {:retry, 100} =
               Retry.decide({:status, 503, :server_error}, 1, [{:idempotent?, true} | base])

      assert {:fail, :ambiguous} =
               Retry.decide({:status, 503, :server_error}, 1, [{:idempotent?, false} | base])

      assert {:retry, 200} =
               Retry.decide({:status, 429, :rate_limited}, 2, [{:idempotent?, false} | base])

      assert {:fail, :rate_limited} =
               Retry.decide({:status, 429, :rate_limited}, 3, [{:idempotent?, true} | base])

      assert {:fail, :not_found} =
               Retry.decide({:status, 404, :not_found}, 1, [{:idempotent?, true} | base])

      assert {:retry, _} =
               Retry.decide({:transport, :nxdomain}, 1, [{:idempotent?, false} | base])

      assert {:fail, :ambiguous} =
               Retry.decide({:transport, :closed}, 1, [{:idempotent?, false} | base])
    end
  end

  describe "disclosure" do
    test "the gate sees the subject before anything is sent" do
      Req.Test.stub(@stub, fn conn -> json(conn, 200, ~s({"id":"w4"})) end)

      assert {:ok, _} =
               Widgets.create_widget(%{name: "w", disclosure_ref: "run-1"}, authorize?: false)

      assert_received {:gate,
                       %{
                         provider: :widgets,
                         operation: :create_widget,
                         effect: :write,
                         disclosure_ref: "run-1"
                       }}
    end

    test "a refusal sends nothing" do
      counter = counting_stub(fn conn, _ -> json(conn, 200, "{}") end)

      assert {:error, error} =
               Widgets.create_widget(%{name: "w", disclosure_ref: "refuse"}, authorize?: false)

      assert %Error{reason: :disclosure_refused, provider_code: "test_refusal"} =
               Error.unwrap(error)

      assert calls(counter) == 0
    end

    test "disclosure_ref is required" do
      assert {:error, %Ash.Error.Invalid{}} =
               Widgets.create_widget(%{name: "w"}, authorize?: false)
    end
  end

  describe "reconcile" do
    setup do
      Req.Test.stub(@stub, fn conn ->
        assert conn.query_params == %{"nameContains" => "ks-abc"}

        json(
          conn,
          200,
          ~s({"data":[{"id":"w1","name":"ks-abc.pdf"},{"id":"w2","name":"ks-abc.pdf"},
                              {"id":"w3","name":"ks-abc-other.pdf"}]})
        )
      end)

      :ok
    end

    defp named(name), do: fn %{"data" => data} -> Enum.filter(data, &(&1["name"] == name)) end

    test "adopts the one match, reports none and duplicates" do
      list = %{name_contains: "ks-abc"}

      assert {:ok, %{"id" => "w3"}} =
               Reconcile.find(Widgets, :create_widget, list, named("ks-abc-other.pdf"),
                 authorize?: false
               )

      assert :none =
               Reconcile.find(Widgets, :create_widget, list, named("ks-zzz.pdf"),
                 authorize?: false
               )

      assert {:many, [_, _]} =
               Reconcile.find(Widgets, :upload_widget, list, named("ks-abc.pdf"),
                 authorize?: false
               )
    end

    test "an operation without a reconcile read cannot be reconciled" do
      assert_raise ArgumentError, fn ->
        Reconcile.find(Widgets, :list_widgets, %{}, & &1, authorize?: false)
      end
    end
  end

  describe "telemetry" do
    test "carries structure only: no path, no query, no body" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "ops-#{inspect(ref)}",
        [:operations_test, :request, :stop],
        fn _event, _measurements, metadata, _ -> send(test_pid, {:stop, metadata}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach("ops-#{inspect(ref)}") end)
      Req.Test.stub(@stub, fn conn -> json(conn, 200, ~s({"id":"w1"})) end)

      assert {:ok, _} = Widgets.get_widget(%{widget_id: "w-secret-id"}, authorize?: false)
      assert_received {:stop, metadata}

      assert %{
               provider: :widgets,
               operation: :get_widget,
               method: :get,
               effect: :read,
               attempts: 1,
               status: 200
             } =
               metadata

      refute inspect(metadata) =~ "w-secret-id"
    end
  end
end
