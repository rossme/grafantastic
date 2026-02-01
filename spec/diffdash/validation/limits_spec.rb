# frozen_string_literal: true

RSpec.describe Diffdash::Validation::Limits do
  let(:config) { Diffdash::Config.new }
  subject(:validator) { described_class.new(config) }

  def create_signal(type:, name: 'test', defining_class: 'Test', metadata: {})
    Diffdash::Signals::Signal.new(
      type: type,
      name: name,
      source_file: '/test.rb',
      defining_class: defining_class,
      inheritance_depth: 0,
      metadata: metadata
    )
  end

  def create_logs(count)
    count.times.map { |i| create_signal(type: :log, name: "log_#{i}") }
  end

  def create_metrics(count, type: :counter)
    count.times.map { |i| create_signal(type: :metric, name: "metric_#{i}", metadata: { metric_type: type }) }
  end

  def create_events(count)
    count.times.map { |i| create_signal(type: :event, name: "event_#{i}") }
  end

  describe '#truncate_and_validate' do
    context 'when within limits' do
      it 'returns all signals when within limits' do
        signals = create_logs(5) + create_metrics(5)

        result = validator.truncate_and_validate(signals)

        expect(result.size).to eq(10)
        expect(validator.warnings).to be_empty
      end

      it 'handles empty signals' do
        result = validator.truncate_and_validate([])

        expect(result).to be_empty
        expect(validator.warnings).to be_empty
      end
    end

    context 'when logs limit exceeded' do
      it 'truncates logs to max limit' do
        signals = create_logs(15)

        result = validator.truncate_and_validate(signals)

        logs = result.select(&:log?)
        expect(logs.size).to eq(10)
        expect(validator.warnings).to include('5 logs not added to dashboard (limit: 10)')
      end
    end

    context 'when metrics limit exceeded' do
      it 'truncates metrics to max limit' do
        signals = create_metrics(15)

        result = validator.truncate_and_validate(signals)

        metrics = result.select(&:metric?)
        expect(metrics.size).to eq(10)
        expect(validator.warnings).to include('5 metrics not added to dashboard (limit: 10)')
      end
    end

    context 'when events limit exceeded' do
      it 'truncates events to max limit' do
        signals = create_events(8)

        result = validator.truncate_and_validate(signals)

        events = result.select(&:event?)
        expect(events.size).to eq(5)
        expect(validator.warnings).to include('3 events not added to dashboard (limit: 5)')
      end
    end

    context 'when panel limit exceeded' do
      it 'truncates signals to fit panel limit' do
        # 10 logs = 10 panels, 5 counters = 5 panels = 15 panels > 12
        signals = create_logs(10) + create_metrics(5)

        result = validator.truncate_and_validate(signals)

        # Should truncate to fit 12 panels (remove 3 logs)
        logs = result.select(&:log?)
        metrics = result.select(&:metric?)

        expect(logs.size + metrics.size).to be <= 12
        expect(validator.warnings).not_to be_empty
        expect(validator.warnings.first).to match(/not added to dashboard \(panel limit: 12\)/)
      end

      it 'counts histogram as 3 panels when truncating' do
        # 10 logs = 10 panels, 1 histogram = 3 panels = 13 panels > 12
        signals = create_logs(10) + create_metrics(1, type: :histogram)

        result = validator.truncate_and_validate(signals)

        # Should remove 1 log to fit (10 - 1 = 9 logs + 1 histogram = 12 panels)
        logs = result.select(&:log?)
        expect(logs.size).to eq(9)
        expect(validator.warnings).to include('1 logs not added to dashboard (panel limit: 12)')
      end

      it 'removes histograms when needed for panel limit' do
        # 8 logs + 2 histograms = 8 + 6 = 14 panels > 12
        signals = create_logs(8) + create_metrics(2, type: :histogram)

        result = validator.truncate_and_validate(signals)

        # Should remove logs first, then histograms if needed
        total_panels = result.select(&:log?).size +
                       result.select(&:metric?).count { |m| m.metadata[:metric_type] == :histogram } * 3

        expect(total_panels).to be <= 12
        expect(validator.warnings).not_to be_empty
      end
    end

    context 'multiple limit violations' do
      it 'applies both type and panel limits' do
        # 15 logs (exceeds log limit of 10) + 15 metrics (exceeds metric limit of 10)
        signals = create_logs(15) + create_metrics(15)

        result = validator.truncate_and_validate(signals)

        logs = result.select(&:log?)
        metrics = result.select(&:metric?)

        # Should first truncate to type limits (10 logs + 10 metrics = 20 panels)
        # Then truncate to panel limit (12 panels)
        expect(logs.size + metrics.size).to be <= 12
        expect(validator.warnings.size).to be >= 2 # At least type limit + panel limit warnings
      end
    end
  end
end
