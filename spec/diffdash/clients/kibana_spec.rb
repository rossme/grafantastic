# frozen_string_literal: true

RSpec.describe Diffdash::Clients::Kibana do
  let(:kibana_url) { "https://kibana.example.com" }
  let(:kibana_api_key) { "test-api-key-123" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_URL").and_return(kibana_url)
    allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_API_KEY").and_return(kibana_api_key)
    allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_USERNAME").and_return(nil)
    allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_PASSWORD").and_return(nil)
    allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_SPACE_ID").and_return(nil)
  end

  describe "architectural boundaries" do
    it "is purely an HTTP client - no business logic" do
      client = described_class.new

      public_methods = client.public_methods(false)

      # Expected: HTTP operations only
      expect(public_methods).to contain_exactly(:health_check!, :import_saved_objects, :list_dashboards, :url)
    end

    it "accepts prepared NDJSON content without modification" do
      client = described_class.new

      ndjson_content = '{"type":"dashboard","id":"123"}'

      stub_request(:post, "#{kibana_url}/api/saved_objects/_import")
        .with(query: { "overwrite" => "true" })
        .to_return(status: 200, body: { success: true, successCount: 1 }.to_json)

      expect { client.import_saved_objects(ndjson_content) }.not_to raise_error
    end

    it "does not depend on Signal objects" do
      client = described_class.new

      expect(client).not_to respond_to(:detect)
      expect(client).not_to respond_to(:render)
      expect(client).not_to respond_to(:extract)
    end
  end

  describe "#initialize" do
    it "accepts explicit url and api_key" do
      client = described_class.new(url: "https://custom.kibana.com", api_key: "custom-key")

      expect(client.url).to eq("https://custom.kibana.com")
    end

    it "falls back to ENV when not provided" do
      client = described_class.new

      expect(client.url).to eq(kibana_url)
    end

    it "raises descriptive error when DIFFDASH_KIBANA_URL missing" do
      allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_URL").and_return(nil)

      expect { described_class.new }.to raise_error(
        Diffdash::Error,
        /DIFFDASH_KIBANA_URL not set/
      )
    end

    it "raises descriptive error when no credentials provided" do
      allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_API_KEY").and_return(nil)
      allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_USERNAME").and_return(nil)
      allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_PASSWORD").and_return(nil)

      expect { described_class.new }.to raise_error(
        Diffdash::Error,
        /DIFFDASH_KIBANA_API_KEY or DIFFDASH_KIBANA_USERNAME\/PASSWORD required/
      )
    end

    it "accepts username/password authentication" do
      allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_API_KEY").and_return(nil)
      allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_USERNAME").and_return("admin")
      allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_PASSWORD").and_return("password")

      expect { described_class.new }.not_to raise_error
    end
  end

  describe "#health_check!" do
    subject(:client) { described_class.new }

    it "returns true on success with /api/status" do
      stub_request(:get, "#{kibana_url}/api/status")
        .to_return(status: 200, body: '{"status": {"overall": {"state": "green"}}}')

      expect(client.health_check!).to be true
    end

    it "tries fallback endpoint if /api/status fails" do
      stub_request(:get, "#{kibana_url}/api/status")
        .to_return(status: 404, body: '{"message": "Not found"}')

      stub_request(:get, "#{kibana_url}/api/saved_objects/_find")
        .with(query: { "type" => "dashboard", "per_page" => "1" })
        .to_return(status: 200, body: '{"saved_objects": []}')

      expect(client.health_check!).to be true
    end

    it "raises ConnectionError on authentication failure" do
      stub_request(:get, "#{kibana_url}/api/status")
        .to_return(status: 401, body: '{"message": "Unauthorized"}')

      expect { client.health_check! }.to raise_error(
        Diffdash::Clients::Kibana::ConnectionError,
        /authentication failed \(401\)/
      )
    end

    it "raises ConnectionError when all endpoints fail" do
      stub_request(:get, "#{kibana_url}/api/status")
        .to_return(status: 500, body: '{"message": "Server error"}')

      stub_request(:get, "#{kibana_url}/api/saved_objects/_find")
        .with(query: { "type" => "dashboard", "per_page" => "1" })
        .to_return(status: 500, body: '{"message": "Server error"}')

      expect { client.health_check! }.to raise_error(
        Diffdash::Clients::Kibana::ConnectionError,
        /health check failed/
      )
    end
  end

  describe "#import_saved_objects" do
    subject(:client) { described_class.new }

    let(:ndjson_content) do
      [
        { type: "index-pattern", id: "idx1", attributes: { title: "logs-*" } },
        { type: "dashboard", id: "dash1", attributes: { title: "Test" } }
      ].map(&:to_json).join("\n")
    end

    it "returns success result on successful import" do
      stub_request(:post, "#{kibana_url}/api/saved_objects/_import")
        .with(query: { "overwrite" => "true" })
        .to_return(
          status: 200,
          body: {
            success: true,
            successCount: 2,
            successResults: [
              { type: "index-pattern", id: "idx1" },
              { type: "dashboard", id: "dash1" }
            ]
          }.to_json
        )

      result = client.import_saved_objects(ndjson_content)

      expect(result[:success]).to be true
      expect(result[:successCount]).to eq(2)
    end

    it "returns dashboard URL on successful import" do
      stub_request(:post, "#{kibana_url}/api/saved_objects/_import")
        .with(query: { "overwrite" => "true" })
        .to_return(
          status: 200,
          body: {
            success: true,
            successCount: 2,
            successResults: [
              { type: "dashboard", id: "my-dashboard-id" }
            ]
          }.to_json
        )

      result = client.import_saved_objects(ndjson_content)

      expect(result[:url]).to include("kibana.example.com")
      expect(result[:url]).to include("my-dashboard-id")
    end

    it "uses space path when space_id is set" do
      client_with_space = described_class.new(space_id: "my-space")

      stub_request(:post, "#{kibana_url}/s/my-space/api/saved_objects/_import")
        .with(query: { "overwrite" => "true" })
        .to_return(
          status: 200,
          body: { success: true, successCount: 1, successResults: [] }.to_json
        )

      expect { client_with_space.import_saved_objects(ndjson_content) }.not_to raise_error
    end

    it "raises error on API failure" do
      stub_request(:post, "#{kibana_url}/api/saved_objects/_import")
        .with(query: { "overwrite" => "true" })
        .to_return(status: 400, body: '{"message": "Invalid NDJSON"}')

      expect { client.import_saved_objects(ndjson_content) }.to raise_error(
        Diffdash::Error,
        /Kibana API error \(400\)/
      )
    end

    it "includes kbn-xsrf header" do
      # Capture the request to verify headers
      request_stub = stub_request(:post, "#{kibana_url}/api/saved_objects/_import")
        .with(query: { "overwrite" => "true" })
        .to_return(status: 200, body: { success: true, successCount: 1 }.to_json)

      client.import_saved_objects(ndjson_content)

      # Verify kbn-xsrf header was included (visible in the WebMock output above)
      expect(request_stub).to have_been_requested
    end
  end

  describe "#list_dashboards" do
    subject(:client) { described_class.new }

    it "returns list of dashboards" do
      stub_request(:get, "#{kibana_url}/api/saved_objects/_find")
        .with(query: { "type" => "dashboard", "per_page" => "100" })
        .to_return(
          status: 200,
          body: {
            saved_objects: [
              { id: "dash1", attributes: { title: "Dashboard 1" } },
              { id: "dash2", attributes: { title: "Dashboard 2" } }
            ]
          }.to_json
        )

      dashboards = client.list_dashboards

      expect(dashboards.size).to eq(2)
      expect(dashboards.first["id"]).to eq("dash1")
    end

    it "returns empty array when no dashboards" do
      stub_request(:get, "#{kibana_url}/api/saved_objects/_find")
        .with(query: { "type" => "dashboard", "per_page" => "100" })
        .to_return(status: 200, body: { saved_objects: [] }.to_json)

      dashboards = client.list_dashboards

      expect(dashboards).to eq([])
    end

    it "raises error on API failure" do
      stub_request(:get, "#{kibana_url}/api/saved_objects/_find")
        .with(query: { "type" => "dashboard", "per_page" => "100" })
        .to_return(status: 500, body: '{"message": "Server error"}')

      expect { client.list_dashboards }.to raise_error(
        Diffdash::Error,
        /Failed to list dashboards/
      )
    end
  end

  describe "authentication" do
    context "with API key" do
      it "sends Authorization header with ApiKey prefix" do
        stub_request(:get, "#{kibana_url}/api/status")
          .with(headers: { "Authorization" => "ApiKey #{kibana_api_key}" })
          .to_return(status: 200, body: '{}')

        client = described_class.new
        client.health_check!

        expect(WebMock).to have_requested(:get, "#{kibana_url}/api/status")
          .with(headers: { "Authorization" => "ApiKey #{kibana_api_key}" })
      end
    end

    context "with username/password" do
      before do
        allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_API_KEY").and_return(nil)
        allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_USERNAME").and_return("admin")
        allow(ENV).to receive(:[]).with("DIFFDASH_KIBANA_PASSWORD").and_return("secret")
      end

      it "sends Basic auth header" do
        stub_request(:get, "#{kibana_url}/api/status")
          .with(basic_auth: ["admin", "secret"])
          .to_return(status: 200, body: '{}')

        client = described_class.new
        client.health_check!

        expect(WebMock).to have_requested(:get, "#{kibana_url}/api/status")
          .with(basic_auth: ["admin", "secret"])
      end
    end
  end
end
