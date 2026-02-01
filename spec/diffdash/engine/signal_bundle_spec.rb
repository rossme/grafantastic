# frozen_string_literal: true

RSpec.describe Diffdash::Engine::SignalBundle do
  let(:log_query) do
    Diffdash::Engine::SignalQuery.new(
      type: :logs,
      name: 'user_logged_in',
      filters: { service: 'auth' },
      time_range: { from: 'now-30m', to: 'now' }
    )
  end

  let(:metric_query) do
    Diffdash::Engine::SignalQuery.new(
      type: :metrics,
      name: 'requests_total',
      metadata: { metric_type: :counter }
    )
  end

  it 'reports empty when all lists are empty' do
    bundle = described_class.new

    expect(bundle.empty?).to be true
  end

  it 'reports non-empty when any list has signals' do
    bundle = described_class.new(logs: [log_query])

    expect(bundle.empty?).to be false
  end

  it 'serializes to a hash' do
    bundle = described_class.new(logs: [log_query], metrics: [metric_query], traces: [], metadata: { foo: 'bar' })

    expect(bundle.to_h).to eq(
      logs: [log_query.to_h],
      metrics: [metric_query.to_h],
      traces: [],
      metadata: { foo: 'bar' }
    )
  end
end
