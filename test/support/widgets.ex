defmodule AshOperations.Test.Widgets do
  @moduledoc "A synthetic provider declared through the operation core, for its tests."
  use Ash.Resource,
    domain: AshOperations.Test.Domain,
    extensions: [AshOperations]

  operations do
    provider :widgets
    transport AshOperations.Test.Transport
    spec "test/fixtures/acme_widgets.openapi.json"
    spec_sha256 "306e2a51a9d8342ef381e377ea9b3b585694a094d8cf2048b9571336e1e2461b"
    disclosure_gate AshOperations.Test.Gate
    telemetry_prefix [:operations_test, :request]

    operation :list_widgets, :get, "/widgets" do
      param :name_contains, :string, as: "nameContains"
      param :page_size, :integer, as: "maxPageSize"
    end

    operation :get_widget, :get, "/widgets/{widget_id}" do
      param :widget_id, :string, in: :path
    end

    operation :get_widget_content, :get, "/widgets/{widget_id}/content" do
      response :binary
      param :widget_id, :string, in: :path
    end

    operation :create_widget, :post, "/widgets" do
      reconcile_with :list_widgets
      discloses? true
      timeout 2_000
      param :name, :string, in: :body, allow_nil?: false
      param :price, :decimal, in: :body
      param :settings, :map, in: :body
    end

    operation :upload_widget, :post, "/widgets/upload" do
      request :multipart
      reconcile_with :list_widgets
      param :file, :map, in: :part, allow_nil?: false
      param :password, :string, in: :part, sensitive?: true
    end

    operation :delete_widget, :delete, "/widgets/{widget_id}" do
      response :none
      param :widget_id, :string, in: :path
    end
  end

  resource do
    require_primary_key? false
  end
end
