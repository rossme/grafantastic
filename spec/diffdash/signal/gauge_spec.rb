# frozen_string_literal: true

RSpec.describe Diffdash::Signal::Gauge do
  subject(:gauge_signal) do
    described_class.new(
      name: 'queue_size',
      source_file: '/app/workers/processor.rb',
      defining_class: 'ProcessorWorker',
      inheritance_depth: 0
    )
  end

  describe '#initialize' do
    it 'sets metric_type to :gauge' do
      expect(gauge_signal.metadata[:metric_type]).to eq(:gauge)
    end
  end

  describe '#metric?' do
    it 'returns true' do
      expect(gauge_signal.metric?).to be true
    end
  end
end
