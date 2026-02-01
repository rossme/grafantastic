# frozen_string_literal: true

RSpec.describe Diffdash::Clients::Grafana do
  let(:grafana_url) { 'https://grafana.example.com' }
  let(:grafana_token) { 'test-token-123' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('GRAFANA_URL').and_return(grafana_url)
    allow(ENV).to receive(:fetch).with('GRAFANA_TOKEN').and_return(grafana_token)
  end

  describe 'architectural boundaries' do
    it 'is purely an HTTP client - no business logic' do
      client = described_class.new

      # Should only have HTTP-related public methods
      public_methods = client.public_methods(false)

      # Expected: HTTP operations only (health_check!, upload, list_folders)
      # NOT expected: signal detection, rendering, validation, etc.
      expect(public_methods).to contain_exactly(:health_check!, :upload, :list_folders, :url)
    end

    it 'accepts prepared payloads without modification' do
      client = described_class.new

      # The client should NOT modify the payload - that's the renderer's job
      arbitrary_payload = { dashboard: { arbitrary: 'data' }, message: 'test' }

      stub_request(:post, "#{grafana_url}/api/dashboards/db")
        .with(body: arbitrary_payload.to_json)
        .to_return(status: 200, body: { id: 1, uid: 'x', url: '/x', status: 'ok' }.to_json)

      expect { client.upload(arbitrary_payload) }.not_to raise_error
    end

    it 'does not depend on Signal objects' do
      # This test ensures the client doesn't know about our domain objects
      client = described_class.new

      # Should work with plain hashes, not Signal objects
      expect(client).not_to respond_to(:detect)
      expect(client).not_to respond_to(:render)
      expect(client).not_to respond_to(:extract)
    end
  end

  describe '#initialize' do
    it 'accepts explicit url and token' do
      client = described_class.new(url: 'https://custom.grafana.com', token: 'custom-token')

      expect(client.url).to eq('https://custom.grafana.com')
    end

    it 'falls back to ENV when not provided' do
      client = described_class.new

      expect(client.url).to eq(grafana_url)
    end

    it 'raises descriptive error when GRAFANA_URL missing' do
      allow(ENV).to receive(:fetch).with('GRAFANA_URL').and_yield

      expect { described_class.new }.to raise_error(
        Diffdash::Error,
        /GRAFANA_URL not set/
      )
    end

    it 'raises descriptive error when GRAFANA_TOKEN missing' do
      allow(ENV).to receive(:fetch).with('GRAFANA_TOKEN').and_yield

      expect { described_class.new }.to raise_error(
        Diffdash::Error,
        /GRAFANA_TOKEN not set/
      )
    end
  end

  describe '#health_check!' do
    subject(:client) { described_class.new }

    it 'returns true on success' do
      stub_request(:get, "#{grafana_url}/api/org")
        .to_return(status: 200, body: '{"id": 1, "name": "Main Org."}')

      expect(client.health_check!).to be true
    end

    it 'raises ConnectionError on authentication failure' do
      stub_request(:get, "#{grafana_url}/api/org")
        .to_return(status: 401, body: '{"message": "Unauthorized"}')

      expect { client.health_check! }.to raise_error(
        Diffdash::Clients::Grafana::ConnectionError,
        /authentication failed \(401\)/
      )
    end

    it 'raises ConnectionError on HTTP error' do
      stub_request(:get, "#{grafana_url}/api/org")
        .to_return(status: 503, body: 'Unavailable')

      expect { client.health_check! }.to raise_error(
        Diffdash::Clients::Grafana::ConnectionError,
        /health check failed \(503\)/
      )
    end

    it 'raises ConnectionError on network failure' do
      stub_request(:get, "#{grafana_url}/api/org")
        .to_raise(Faraday::ConnectionFailed.new('Connection refused'))

      expect { client.health_check! }.to raise_error(
        Diffdash::Clients::Grafana::ConnectionError,
        /Cannot connect to Grafana/
      )
    end
  end

  describe '#upload' do
    subject(:client) { described_class.new }

    let(:payload) { { dashboard: { title: 'Test' }, overwrite: true } }
    let(:response_body) do
      { 'id' => 42, 'uid' => 'test-uid', 'url' => '/d/test-uid/test', 'status' => 'success' }
    end

    before do
      stub_request(:post, "#{grafana_url}/api/dashboards/db")
        .to_return(status: 200, body: response_body.to_json)
    end

    it 'posts JSON to Grafana API' do
      client.upload(payload)

      expect(WebMock).to have_requested(:post, "#{grafana_url}/api/dashboards/db")
        .with(
          body: payload.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'includes authorization header' do
      client.upload(payload)

      expect(WebMock).to have_requested(:post, "#{grafana_url}/api/dashboards/db")
        .with(headers: { 'Authorization' => "Bearer #{grafana_token}" })
    end

    it 'returns structured response' do
      result = client.upload(payload)

      expect(result).to include(
        id: 42,
        uid: 'test-uid',
        url: "#{grafana_url}/d/test-uid/test",
        status: 'success'
      )
    end

    it 'constructs absolute URL from relative path' do
      result = client.upload(payload)

      expect(result[:url]).to start_with(grafana_url)
    end

    it 'raises on API error' do
      stub_request(:post, "#{grafana_url}/api/dashboards/db")
        .to_return(status: 400, body: { message: 'Bad request' }.to_json)

      expect { client.upload(payload) }.to raise_error(
        Diffdash::Error,
        /Grafana API error \(400\)/
      )
    end
  end

  describe '#list_folders' do
    subject(:client) { described_class.new }

    let(:folders_response) do
      [
        { 'id' => 1, 'title' => 'Production' },
        { 'id' => 2, 'title' => 'Staging' }
      ]
    end

    before do
      stub_request(:get, "#{grafana_url}/api/folders")
        .to_return(status: 200, body: folders_response.to_json)
    end

    it 'fetches folders from Grafana API' do
      result = client.list_folders

      expect(result).to eq(folders_response)
    end

    it 'includes authorization header' do
      client.list_folders

      expect(WebMock).to have_requested(:get, "#{grafana_url}/api/folders")
        .with(headers: { 'Authorization' => "Bearer #{grafana_token}" })
    end

    it 'raises ConnectionError on failure' do
      stub_request(:get, "#{grafana_url}/api/folders")
        .to_return(status: 403, body: { message: 'Forbidden' }.to_json)

      expect { client.list_folders }.to raise_error(
        Diffdash::Clients::Grafana::ConnectionError,
        /Failed to list folders \(403\)/
      )
    end

    it 'raises ConnectionError on network failure' do
      stub_request(:get, "#{grafana_url}/api/folders")
        .to_raise(Faraday::TimeoutError.new('Timeout'))

      expect { client.list_folders }.to raise_error(
        Diffdash::Clients::Grafana::ConnectionError,
        /Cannot connect to Grafana/
      )
    end
  end
end
