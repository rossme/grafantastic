# frozen_string_literal: true

RSpec.describe Diffdash::Outputs::Kibana do
  describe '#render' do
    context 'with empty signals' do
      subject(:renderer) { described_class.new(title: 'Empty Dashboard') }
      let(:bundle) do
        Diffdash::Engine::SignalBundle.new(
          metadata: {
            time_range: { from: 'now-30m', to: 'now' },
            change_set: { branch_name: 'feature/pr-123' }
          }
        )
      end

      it 'returns valid Kibana structure' do
        result = renderer.render(bundle)

        expect(result).to have_key(:dashboard)
        expect(result).to have_key(:visualizations)
        expect(result).to have_key(:index_pattern)
      end

      it 'includes index pattern' do
        result = renderer.render(bundle)

        expect(result[:index_pattern][:type]).to eq('index-pattern')
        expect(result[:index_pattern][:attributes][:title]).to eq('logs-*')
      end

      it 'creates empty visualizations array' do
        result = renderer.render(bundle)
        expect(result[:visualizations]).to eq([])
      end
    end

    context 'with log signals' do
      let(:log_signal) do
        Diffdash::Signal::Log.new(
          name: 'payment_processed',
          source_file: '/app/services/payment.rb',
          defining_class: 'PaymentService',
          inheritance_depth: 0,
          metadata: { level: :info, line: 42 }
        )
      end

      subject(:renderer) { described_class.new(title: 'Test Dashboard') }
      let(:bundle) do
        Diffdash::Engine::SignalBundle.new(
          logs: [log_signal],
          metrics: [],
          traces: [],
          metadata: {
            time_range: { from: 'now-30m', to: 'now' },
            change_set: { branch_name: 'test-branch' }
          }
        )
      end

      it 'creates saved search for log' do
        result = renderer.render(bundle)
        visualizations = result[:visualizations]

        expect(visualizations.size).to eq(1)
        expect(visualizations.first[:type]).to eq('search')
        expect(visualizations.first[:attributes][:title]).to include('payment_processed')
      end

      it 'includes KQL query for log message' do
        result = renderer.render(bundle)
        viz = result[:visualizations].first
        search_source = JSON.parse(viz[:attributes][:kibanaSavedObjectMeta][:searchSourceJSON])

        expect(search_source['query']['query']).to eq('message:"payment_processed"')
        expect(search_source['query']['language']).to eq('kuery')
      end

      it 'sets dashboard title' do
        result = renderer.render(bundle)
        expect(result[:dashboard][:attributes][:title]).to eq('Test Dashboard')
      end

      it 'includes dashboard description with branch' do
        result = renderer.render(bundle)
        description = result[:dashboard][:attributes][:description]

        expect(description).to include('test-branch')
        expect(description).to include('1 log')
      end
    end

    context 'with metric signals' do
      let(:counter_signal) do
        Diffdash::Signal::Counter.new(
          name: 'orders_processed',
          source_file: '/app/services/orders.rb',
          defining_class: 'OrderService',
          inheritance_depth: 0,
          metadata: { metric_type: :counter }
        )
      end

      let(:gauge_signal) do
        Diffdash::Signal::Gauge.new(
          name: 'queue_size',
          source_file: '/app/services/queue.rb',
          defining_class: 'QueueService',
          inheritance_depth: 0,
          metadata: { metric_type: :gauge }
        )
      end

      subject(:renderer) { described_class.new(title: 'Metrics Dashboard') }
      let(:bundle) do
        Diffdash::Engine::SignalBundle.new(
          logs: [],
          metrics: [counter_signal, gauge_signal],
          traces: [],
          metadata: {
            time_range: { from: 'now-30m', to: 'now' },
            change_set: { branch_name: 'metrics-branch' }
          }
        )
      end

      it 'creates visualization for counter' do
        result = renderer.render(bundle)
        counter_viz = result[:visualizations].find { |v| v[:attributes][:title].include?('orders_processed') }

        expect(counter_viz).not_to be_nil
        expect(counter_viz[:type]).to eq('visualization')
      end

      it 'creates visualization for gauge' do
        result = renderer.render(bundle)
        gauge_viz = result[:visualizations].find { |v| v[:attributes][:title].include?('queue_size') }

        expect(gauge_viz).not_to be_nil
        expect(gauge_viz[:type]).to eq('visualization')
      end
    end

    context 'with custom index pattern' do
      subject(:renderer) { described_class.new(title: 'Custom Index', index_pattern: 'logs-myapp-*') }
      let(:bundle) do
        Diffdash::Engine::SignalBundle.new(
          metadata: { change_set: { branch_name: 'test' } }
        )
      end

      it 'uses custom index pattern' do
        result = renderer.render(bundle)
        expect(result[:index_pattern][:attributes][:title]).to eq('logs-myapp-*')
      end
    end
  end

  describe '#upload' do
    let(:bundle) do
      Diffdash::Engine::SignalBundle.new(
        logs: [
          Diffdash::Signal::Log.new(
            name: 'test_log',
            source_file: 'test.rb',
            defining_class: 'TestClass',
            inheritance_depth: 0,
            metadata: { level: :info }
          )
        ],
        metadata: { change_set: { branch_name: 'test' } }
      )
    end

    context 'with dry_run' do
      subject(:renderer) { described_class.new(title: 'Test', dry_run: true) }

      it 'does not write file' do
        payload = renderer.render(bundle)
        result = renderer.upload(payload)

        expect(result[:url]).to be_nil
        expect(File.exist?('diffdash-kibana-dashboard.ndjson')).to be false
      end
    end

    context 'without credentials' do
      subject(:renderer) { described_class.new(title: 'Test', dry_run: false) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DIFFDASH_KIBANA_URL').and_return(nil)
        allow(ENV).to receive(:[]).with('DIFFDASH_KIBANA_API_KEY').and_return(nil)
        allow(ENV).to receive(:[]).with('DIFFDASH_KIBANA_USERNAME').and_return(nil)
        allow(ENV).to receive(:[]).with('DIFFDASH_KIBANA_PASSWORD').and_return(nil)
      end

      after do
        File.delete('diffdash-kibana-dashboard.ndjson') if File.exist?('diffdash-kibana-dashboard.ndjson')
      end

      it 'writes NDJSON file' do
        payload = renderer.render(bundle)
        result = renderer.upload(payload)

        expect(result[:file]).to eq('diffdash-kibana-dashboard.ndjson')
        expect(File.exist?('diffdash-kibana-dashboard.ndjson')).to be true
      end

      it 'writes valid NDJSON format' do
        payload = renderer.render(bundle)
        renderer.upload(payload)

        content = File.read('diffdash-kibana-dashboard.ndjson')
        lines = content.split("\n")

        lines.each do |line|
          expect { JSON.parse(line) }.not_to raise_error
        end
      end
    end

    context 'with API credentials' do
      let(:kibana_url) { 'https://kibana.example.com' }
      let(:kibana_api_key) { 'test-api-key' }

      subject(:renderer) { described_class.new(title: 'Test', dry_run: false, verbose: false) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DIFFDASH_KIBANA_URL').and_return(kibana_url)
        allow(ENV).to receive(:[]).with('DIFFDASH_KIBANA_API_KEY').and_return(kibana_api_key)
        allow(ENV).to receive(:[]).with('DIFFDASH_KIBANA_USERNAME').and_return(nil)
        allow(ENV).to receive(:[]).with('DIFFDASH_KIBANA_PASSWORD').and_return(nil)
        allow(ENV).to receive(:[]).with('DIFFDASH_KIBANA_SPACE_ID').and_return(nil)
      end

      it 'uploads via API when credentials present' do
        # Stub health check
        stub_request(:get, "#{kibana_url}/api/status")
          .to_return(status: 200, body: '{"status": "ok"}')

        # Stub import
        stub_request(:post, "#{kibana_url}/api/saved_objects/_import")
          .with(query: { 'overwrite' => 'true' })
          .to_return(
            status: 200,
            body: {
              success: true,
              successCount: 3,
              successResults: [{ type: 'dashboard', id: 'abc123' }]
            }.to_json
          )

        payload = renderer.render(bundle)
        result = renderer.upload(payload)

        expect(result[:url]).to include('kibana.example.com')
        expect(result[:url]).to include('abc123')
      end
    end
  end

  describe 'NDJSON format' do
    subject(:renderer) { described_class.new(title: 'NDJSON Test') }

    let(:bundle) do
      Diffdash::Engine::SignalBundle.new(
        logs: [
          Diffdash::Signal::Log.new(
            name: 'log1',
            source_file: 'test.rb',
            defining_class: 'TestClass',
            inheritance_depth: 0,
            metadata: { level: :info }
          ),
          Diffdash::Signal::Log.new(
            name: 'log2',
            source_file: 'test.rb',
            defining_class: 'TestClass',
            inheritance_depth: 0,
            metadata: { level: :error }
          )
        ],
        metadata: { change_set: { branch_name: 'test' } }
      )
    end

    it 'generates correct number of NDJSON lines' do
      payload = renderer.render(bundle)
      ndjson = renderer.send(:build_ndjson, payload)
      lines = ndjson.split("\n")

      # 1 index pattern + 2 visualizations + 1 dashboard = 4 lines
      expect(lines.size).to eq(4)
    end

    it 'includes all required object types' do
      payload = renderer.render(bundle)
      ndjson = renderer.send(:build_ndjson, payload)
      lines = ndjson.split("\n")
      types = lines.map { |l| JSON.parse(l)['type'] }

      expect(types).to include('index-pattern')
      expect(types).to include('search')
      expect(types).to include('dashboard')
    end
  end
end
