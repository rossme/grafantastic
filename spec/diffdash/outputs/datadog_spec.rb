# frozen_string_literal: true

RSpec.describe Diffdash::Outputs::Datadog do
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

      it 'returns valid Datadog dashboard structure' do
        result = renderer.render(bundle)

        expect(result).to have_key(:title)
        expect(result).to have_key(:description)
        expect(result).to have_key(:widgets)
        expect(result).to have_key(:layout_type)
        expect(result).to have_key(:template_variables)
      end

      it 'sets dashboard title' do
        result = renderer.render(bundle)
        expect(result[:title]).to eq('Empty Dashboard')
      end

      it 'creates empty widgets array' do
        result = renderer.render(bundle)
        expect(result[:widgets]).to eq([])
      end

      it 'includes diffdash tags' do
        result = renderer.render(bundle)
        expect(result[:tags]).to include('diffdash')
      end

      it 'uses ordered layout' do
        result = renderer.render(bundle)
        expect(result[:layout_type]).to eq('ordered')
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
          metadata: { time_range: { from: 'now-30m', to: 'now' } }
        )
      end

      it 'creates log_stream widget' do
        result = renderer.render(bundle)
        widgets = result[:widgets]

        expect(widgets.size).to eq(1)
        expect(widgets.first[:definition][:type]).to eq('log_stream')
      end

      it 'includes log name in widget title' do
        result = renderer.render(bundle)
        widget = result[:widgets].first

        expect(widget[:definition][:title]).to include('payment_processed')
      end

      it 'includes log query with message filter' do
        result = renderer.render(bundle)
        widget = result[:widgets].first
        query = widget[:definition][:query]

        expect(query).to include('payment_processed')
        expect(query).to include('env:$env')
        expect(query).to include('service:$service')
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

      let(:histogram_signal) do
        Diffdash::Signal::Histogram.new(
          name: 'request_duration',
          source_file: '/app/services/api.rb',
          defining_class: 'ApiService',
          inheritance_depth: 0,
          metadata: { metric_type: :histogram }
        )
      end

      subject(:renderer) { described_class.new(title: 'Metrics Dashboard') }
      let(:bundle) do
        Diffdash::Engine::SignalBundle.new(
          logs: [],
          metrics: [counter_signal, gauge_signal, histogram_signal],
          traces: [],
          metadata: { time_range: { from: 'now-30m', to: 'now' } }
        )
      end

      it 'creates timeseries widget for counter' do
        result = renderer.render(bundle)
        counter_widget = result[:widgets].find { |w| w[:definition][:title].include?('orders_processed') }

        expect(counter_widget[:definition][:type]).to eq('timeseries')
        expect(counter_widget[:definition][:requests].first[:q]).to include('as_rate()')
      end

      it 'creates timeseries widget for gauge' do
        result = renderer.render(bundle)
        gauge_widget = result[:widgets].find { |w| w[:definition][:title].include?('queue_size') }

        expect(gauge_widget[:definition][:type]).to eq('timeseries')
        expect(gauge_widget[:definition][:requests].first[:q]).to include('avg:')
      end

      it 'creates timeseries widget for histogram with percentiles' do
        result = renderer.render(bundle)
        histogram_widget = result[:widgets].find { |w| w[:definition][:title].include?('request_duration') }

        expect(histogram_widget[:definition][:type]).to eq('timeseries')
        expect(histogram_widget[:definition][:requests].size).to eq(2)
        expect(histogram_widget[:definition][:requests].first[:q]).to include('95percentile')
        expect(histogram_widget[:definition][:requests].last[:q]).to include('median')
      end
    end

    context 'template variables' do
      subject(:renderer) { described_class.new(title: 'Test') }
      let(:bundle) do
        Diffdash::Engine::SignalBundle.new(
          metadata: { change_set: { branch_name: 'test' } }
        )
      end

      it 'includes env variable' do
        result = renderer.render(bundle)
        env_var = result[:template_variables].find { |v| v[:name] == 'env' }

        expect(env_var).not_to be_nil
        expect(env_var[:prefix]).to eq('env')
        expect(env_var[:available_values]).to include('production', 'staging')
      end

      it 'includes service variable' do
        result = renderer.render(bundle)
        service_var = result[:template_variables].find { |v| v[:name] == 'service' }

        expect(service_var).not_to be_nil
        expect(service_var[:prefix]).to eq('service')
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

      it 'does not call Datadog API' do
        expect(Diffdash::Clients::Datadog).not_to receive(:new)

        payload = renderer.render(bundle)
        result = renderer.upload(payload)

        expect(result[:url]).to be_nil
      end
    end

    context 'with API credentials' do
      let(:datadog_api_key) { 'test-api-key' }
      let(:datadog_app_key) { 'test-app-key' }

      subject(:renderer) { described_class.new(title: 'Test', dry_run: false, verbose: false) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DIFFDASH_DATADOG_API_KEY').and_return(datadog_api_key)
        allow(ENV).to receive(:[]).with('DIFFDASH_DATADOG_APP_KEY').and_return(datadog_app_key)
        allow(ENV).to receive(:[]).with('DIFFDASH_DATADOG_SITE').and_return(nil)
      end

      it 'uploads via API and returns URL' do
        stub_request(:get, 'https://api.datadoghq.com/api/v1/validate')
          .to_return(status: 200, body: '{"valid": true}')

        stub_request(:post, 'https://api.datadoghq.com/api/v1/dashboard')
          .to_return(
            status: 200,
            body: { id: 'abc-123', url: '/dashboard/abc-123' }.to_json
          )

        payload = renderer.render(bundle)
        result = renderer.upload(payload)

        expect(result[:url]).to include('datadoghq.com')
        expect(result[:url]).to include('abc-123')
      end
    end
  end

  describe 'metric name sanitization' do
    subject(:renderer) { described_class.new(title: 'Test') }

    it 'converts to lowercase' do
      result = renderer.send(:sanitize_metric_name, 'MyMetric')
      expect(result).to eq('mymetric')
    end

    it 'replaces special characters with underscores' do
      result = renderer.send(:sanitize_metric_name, 'my-metric/name')
      expect(result).to eq('my_metric_name')
    end

    it 'preserves dots for namespacing' do
      result = renderer.send(:sanitize_metric_name, 'app.orders.count')
      expect(result).to eq('app.orders.count')
    end
  end
end
