# frozen_string_literal: true

RSpec.describe Diffdash::Clients::Datadog do
  let(:datadog_api_key) { "test-api-key-123" }
  let(:datadog_app_key) { "test-app-key-456" }
  let(:datadog_site) { "datadoghq.com" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DIFFDASH_DATADOG_API_KEY").and_return(datadog_api_key)
    allow(ENV).to receive(:[]).with("DIFFDASH_DATADOG_APP_KEY").and_return(datadog_app_key)
    allow(ENV).to receive(:[]).with("DIFFDASH_DATADOG_SITE").and_return(nil)
  end

  describe "architectural boundaries" do
    it "is purely an HTTP client - no business logic" do
      client = described_class.new

      public_methods = client.public_methods(false)

      # Expected: HTTP operations only
      expect(public_methods).to contain_exactly(:health_check!, :upload_dashboard, :url)
    end

    it "accepts prepared dashboard payload without modification" do
      client = described_class.new

      arbitrary_payload = { title: "Test", widgets: [], layout_type: "ordered" }

      stub_request(:post, "https://api.#{datadog_site}/api/v1/dashboard")
        .with(body: arbitrary_payload.to_json)
        .to_return(status: 200, body: { id: "abc-123" }.to_json)

      expect { client.upload_dashboard(arbitrary_payload) }.not_to raise_error
    end

    it "does not depend on Signal objects" do
      client = described_class.new

      expect(client).not_to respond_to(:detect)
      expect(client).not_to respond_to(:render)
      expect(client).not_to respond_to(:extract)
    end
  end

  describe "#initialize" do
    it "accepts explicit api_key and app_key" do
      client = described_class.new(api_key: "custom-api", app_key: "custom-app")

      expect(client.url).to eq("https://api.datadoghq.com")
    end

    it "accepts custom site" do
      client = described_class.new(site: "datadoghq.eu")

      expect(client.url).to eq("https://api.datadoghq.eu")
    end

    it "falls back to ENV when not provided" do
      client = described_class.new

      expect(client.url).to eq("https://api.datadoghq.com")
    end

    it "raises descriptive error when DIFFDASH_DATADOG_API_KEY missing" do
      allow(ENV).to receive(:[]).with("DIFFDASH_DATADOG_API_KEY").and_return(nil)

      expect { described_class.new }.to raise_error(
        Diffdash::Error,
        /DIFFDASH_DATADOG_API_KEY not set/
      )
    end

    it "raises descriptive error when DIFFDASH_DATADOG_APP_KEY missing" do
      allow(ENV).to receive(:[]).with("DIFFDASH_DATADOG_APP_KEY").and_return(nil)

      expect { described_class.new }.to raise_error(
        Diffdash::Error,
        /DIFFDASH_DATADOG_APP_KEY not set/
      )
    end
  end

  describe "#health_check!" do
    subject(:client) { described_class.new }

    it "returns true on success" do
      stub_request(:get, "https://api.#{datadog_site}/api/v1/validate")
        .to_return(status: 200, body: '{"valid": true}')

      expect(client.health_check!).to be true
    end

    it "raises ConnectionError on authentication failure" do
      stub_request(:get, "https://api.#{datadog_site}/api/v1/validate")
        .to_return(status: 403, body: '{"errors": ["Forbidden"]}')

      expect { client.health_check! }.to raise_error(
        Diffdash::Clients::Datadog::ConnectionError,
        /authentication failed \(403\)/
      )
    end

    it "raises ConnectionError on other failures" do
      stub_request(:get, "https://api.#{datadog_site}/api/v1/validate")
        .to_return(status: 500, body: '{"errors": ["Server error"]}')

      expect { client.health_check! }.to raise_error(
        Diffdash::Clients::Datadog::ConnectionError,
        /health check failed \(500\)/
      )
    end

    it "raises ConnectionError on network error" do
      stub_request(:get, "https://api.#{datadog_site}/api/v1/validate")
        .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

      expect { client.health_check! }.to raise_error(
        Diffdash::Clients::Datadog::ConnectionError,
        /Cannot connect to Datadog/
      )
    end
  end

  describe "#upload_dashboard" do
    subject(:client) { described_class.new }

    let(:dashboard_payload) do
      {
        title: "Test Dashboard",
        description: "Auto-generated",
        widgets: [],
        layout_type: "ordered"
      }
    end

    it "returns success result with dashboard ID and URL" do
      stub_request(:post, "https://api.#{datadog_site}/api/v1/dashboard")
        .to_return(
          status: 200,
          body: {
            id: "abc-123",
            title: "Test Dashboard"
          }.to_json
        )

      result = client.upload_dashboard(dashboard_payload)

      expect(result[:id]).to eq("abc-123")
      expect(result[:url]).to eq("https://app.datadoghq.com/dashboard/abc-123")
    end

    it "sends correct headers" do
      stub_request(:post, "https://api.#{datadog_site}/api/v1/dashboard")
        .with(
          headers: {
            "DD-API-KEY" => datadog_api_key,
            "DD-APPLICATION-KEY" => datadog_app_key,
            "Content-Type" => "application/json"
          }
        )
        .to_return(status: 200, body: { id: "abc-123" }.to_json)

      client.upload_dashboard(dashboard_payload)

      expect(WebMock).to have_requested(:post, "https://api.#{datadog_site}/api/v1/dashboard")
        .with(headers: { "DD-API-KEY" => datadog_api_key })
    end

    it "raises error on API failure" do
      stub_request(:post, "https://api.#{datadog_site}/api/v1/dashboard")
        .to_return(
          status: 400,
          body: { errors: ["Invalid dashboard definition"] }.to_json
        )

      expect { client.upload_dashboard(dashboard_payload) }.to raise_error(
        Diffdash::Error,
        /Datadog API error \(400\): Invalid dashboard definition/
      )
    end

    it "handles non-JSON error responses" do
      stub_request(:post, "https://api.#{datadog_site}/api/v1/dashboard")
        .to_return(status: 500, body: "Internal Server Error")

      expect { client.upload_dashboard(dashboard_payload) }.to raise_error(
        Diffdash::Error,
        /Datadog API error \(500\)/
      )
    end
  end

  describe "regional sites" do
    it "supports EU site" do
      allow(ENV).to receive(:[]).with("DIFFDASH_DATADOG_SITE").and_return("datadoghq.eu")

      client = described_class.new

      expect(client.url).to eq("https://api.datadoghq.eu")
    end

    it "supports US3 site" do
      client = described_class.new(site: "us3.datadoghq.com")

      expect(client.url).to eq("https://api.us3.datadoghq.com")
    end

    it "supports US5 site" do
      client = described_class.new(site: "us5.datadoghq.com")

      expect(client.url).to eq("https://api.us5.datadoghq.com")
    end

    it "generates correct dashboard URL for EU site" do
      client = described_class.new(site: "datadoghq.eu")

      stub_request(:post, "https://api.datadoghq.eu/api/v1/dashboard")
        .to_return(status: 200, body: { id: "xyz-789" }.to_json)

      result = client.upload_dashboard({ title: "Test" })

      expect(result[:url]).to eq("https://app.datadoghq.eu/dashboard/xyz-789")
    end
  end
end
