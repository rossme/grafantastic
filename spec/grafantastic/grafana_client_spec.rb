# frozen_string_literal: true

RSpec.describe Grafantastic::GrafanaClient do
  let(:grafana_url) { "https://grafana.example.com" }
  let(:grafana_token) { "test-token-123" }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("GRAFANA_URL").and_return(grafana_url)
    allow(ENV).to receive(:fetch).with("GRAFANA_TOKEN").and_return(grafana_token)
  end

  describe "#initialize" do
    it "reads GRAFANA_URL from environment" do
      expect { described_class.new }.not_to raise_error
    end

    it "raises error when GRAFANA_URL is not set" do
      allow(ENV).to receive(:fetch).with("GRAFANA_URL").and_yield

      expect { described_class.new }.to raise_error(Grafantastic::Error, /GRAFANA_URL not set/)
    end

    it "raises error when GRAFANA_TOKEN is not set" do
      allow(ENV).to receive(:fetch).with("GRAFANA_URL").and_return(grafana_url)
      allow(ENV).to receive(:fetch).with("GRAFANA_TOKEN").and_yield

      expect { described_class.new }.to raise_error(Grafantastic::Error, /GRAFANA_TOKEN not set/)
    end
  end

  describe "#health_check!" do
    subject(:client) { described_class.new }

    context "when Grafana is healthy" do
      before do
        stub_request(:get, "#{grafana_url}/api/health")
          .to_return(status: 200, body: '{"database": "ok"}')
      end

      it "returns true" do
        expect(client.health_check!).to be true
      end

      it "does not raise" do
        expect { client.health_check! }.not_to raise_error
      end
    end

    context "when Grafana returns non-200" do
      before do
        stub_request(:get, "#{grafana_url}/api/health")
          .to_return(status: 503, body: "Service Unavailable")
      end

      it "raises ConnectionError" do
        expect { client.health_check! }.to raise_error(
          Grafantastic::GrafanaClient::ConnectionError,
          /health check failed \(503\)/
        )
      end
    end

    context "when connection fails" do
      before do
        stub_request(:get, "#{grafana_url}/api/health")
          .to_raise(Faraday::ConnectionFailed.new("Connection refused"))
      end

      it "raises ConnectionError with connection details" do
        expect { client.health_check! }.to raise_error(
          Grafantastic::GrafanaClient::ConnectionError,
          /Cannot connect to Grafana/
        )
      end
    end
  end

  describe "#upload" do
    subject(:client) { described_class.new }

    let(:dashboard_payload) do
      {
        dashboard: { title: "Test Dashboard", panels: [] },
        overwrite: true
      }
    end

    let(:success_response) do
      {
        "id" => 123,
        "uid" => "abc123",
        "url" => "/d/abc123/test-dashboard",
        "status" => "success"
      }
    end

    before do
      stub_request(:post, "#{grafana_url}/api/dashboards/db")
        .to_return(
          status: 200,
          body: success_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "posts to Grafana API" do
      client.upload(dashboard_payload)

      expect(WebMock).to have_requested(:post, "#{grafana_url}/api/dashboards/db")
    end

    it "sends dashboard as JSON body" do
      client.upload(dashboard_payload)

      expect(WebMock).to have_requested(:post, "#{grafana_url}/api/dashboards/db")
        .with(body: dashboard_payload.to_json)
    end

    it "includes authorization header" do
      client.upload(dashboard_payload)

      expect(WebMock).to have_requested(:post, "#{grafana_url}/api/dashboards/db")
        .with(headers: { "Authorization" => "Bearer #{grafana_token}" })
    end

    it "sets content-type to application/json" do
      client.upload(dashboard_payload)

      expect(WebMock).to have_requested(:post, "#{grafana_url}/api/dashboards/db")
        .with(headers: { "Content-Type" => "application/json" })
    end

    it "returns parsed response" do
      result = client.upload(dashboard_payload)

      expect(result[:id]).to eq(123)
      expect(result[:uid]).to eq("abc123")
      expect(result[:status]).to eq("success")
    end

    it "constructs full URL in response" do
      result = client.upload(dashboard_payload)

      expect(result[:url]).to eq("#{grafana_url}/d/abc123/test-dashboard")
    end

    context "when API returns error" do
      before do
        stub_request(:post, "#{grafana_url}/api/dashboards/db")
          .to_return(
            status: 400,
            body: { "message" => "Invalid dashboard" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises error with status code" do
        expect { client.upload(dashboard_payload) }.to raise_error(
          Grafantastic::Error,
          /Grafana API error \(400\)/
        )
      end

      it "includes error message from response" do
        expect { client.upload(dashboard_payload) }.to raise_error(
          Grafantastic::Error,
          /Invalid dashboard/
        )
      end
    end

    context "when API returns 401 unauthorized" do
      before do
        stub_request(:post, "#{grafana_url}/api/dashboards/db")
          .to_return(
            status: 401,
            body: { "message" => "Unauthorized" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises error" do
        expect { client.upload(dashboard_payload) }.to raise_error(
          Grafantastic::Error,
          /Grafana API error \(401\): Unauthorized/
        )
      end
    end

    context "when API returns 500 server error" do
      before do
        stub_request(:post, "#{grafana_url}/api/dashboards/db")
          .to_return(
            status: 500,
            body: "Internal Server Error",
            headers: { "Content-Type" => "text/plain" }
          )
      end

      it "raises error with raw body" do
        expect { client.upload(dashboard_payload) }.to raise_error(
          Grafantastic::Error,
          /Grafana API error \(500\)/
        )
      end
    end
  end
end
