# frozen_string_literal: true

RSpec.describe Diffdash::Detectors::RubyDetector do
  subject(:detector) { described_class.new }

  describe '#detect' do
    it 'detects log signals from Ruby source' do
      source = <<~RUBY
        class PaymentProcessor
          def process
            Rails.logger.info "payment_processed"
          end
        end
      RUBY

      signals = detector.detect(source: source, file_path: '/app/payment.rb')

      expect(signals).not_to be_empty
      expect(signals.first).to be_a(Diffdash::Signal::Log)
      expect(signals.first.name).to eq('payment_processed')
    end

    it 'detects metric signals from Ruby source' do
      source = <<~RUBY
        class MetricsService
          def track
            StatsD.increment("requests_total")
          end
        end
      RUBY

      signals = detector.detect(source: source, file_path: '/app/metrics.rb')

      expect(signals).not_to be_empty
      expect(signals.first).to be_a(Diffdash::Signal::Counter)
      expect(signals.first.name).to eq('requests_total')
    end

    it 'returns empty array for source without signals' do
      source = <<~RUBY
        class User
          def name
            "John"
          end
        end
      RUBY

      signals = detector.detect(source: source, file_path: '/app/user.rb')

      expect(signals).to be_empty
    end

    it 'respects inheritance_depth parameter' do
      source = <<~RUBY
        class Base
          def log
            logger.info "base_event"
          end
        end
      RUBY

      signals = detector.detect(source: source, file_path: '/app/base.rb', inheritance_depth: 2)

      expect(signals.first.inheritance_depth).to eq(2)
    end
  end

  describe '#detect_with_metadata' do
    it 'returns signals and dynamic metrics' do
      source = <<~RUBY
        class Service
          def track
            Rails.logger.info "event"
            StatsD.increment(metric_name)
          end
        end
      RUBY

      result = detector.detect_with_metadata(source: source, file_path: '/app/service.rb')

      expect(result).to have_key(:signals)
      expect(result).to have_key(:dynamic_metrics)
      expect(result[:signals].size).to eq(1)
      expect(result[:dynamic_metrics].size).to eq(1)
    end
  end

  describe '#detect_structure' do
    it 'extracts class definitions' do
      source = <<~RUBY
        class PaymentProcessor < BaseProcessor
          include Loggable
          prepend Metrics
        end
      RUBY

      structure = detector.detect_structure(source: source, file_path: '/app/payment.rb')

      expect(structure[:class_definitions]).not_to be_empty
      expect(structure[:class_definitions].first[:name]).to eq('PaymentProcessor')
      expect(structure[:class_definitions].first[:parent]).to eq('BaseProcessor')
    end

    it 'extracts included modules' do
      source = <<~RUBY
        class Service
          include Loggable
        end
      RUBY

      structure = detector.detect_structure(source: source, file_path: '/app/service.rb')

      expect(structure[:included_modules]).not_to be_empty
      expect(structure[:included_modules].first[:module_name]).to eq('Loggable')
    end

    it 'extracts prepended modules' do
      source = <<~RUBY
        class Service
          prepend Metrics
        end
      RUBY

      structure = detector.detect_structure(source: source, file_path: '/app/service.rb')

      expect(structure[:prepended_modules]).not_to be_empty
      expect(structure[:prepended_modules].first[:module_name]).to eq('Metrics')
    end

    it 'returns default structure for invalid source' do
      structure = detector.detect_structure(source: 'invalid ruby', file_path: '/app/bad.rb')

      expect(structure[:class_definitions]).to eq([])
      expect(structure[:included_modules]).to eq([])
      expect(structure[:prepended_modules]).to eq([])
    end
  end
end
