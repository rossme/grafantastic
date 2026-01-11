# frozen_string_literal: true

RSpec.describe Grafantastic::Services::SignalCollector do
  subject(:collector) { described_class.new }

  describe "#collect" do
    context "with simple Ruby file" do
      let(:temp_file) do
        file = Tempfile.new(["test", ".rb"])
        file.write(<<~RUBY)
          class PaymentProcessor
            def process
              Rails.logger.info "payment_processed"
              StatsD.increment("payments_total")
            end
          end
        RUBY
        file.close
        file
      end

      after { temp_file.unlink }

      it "collects signals from the file" do
        signals = collector.collect([temp_file.path])

        expect(signals).not_to be_empty
        expect(signals.map(&:name)).to include("payment_processed", "payments_total")
      end

      it "returns Signal objects" do
        signals = collector.collect([temp_file.path])

        expect(signals.first).to be_a(Grafantastic::Signal::Base)
      end

      it "deduplicates identical signals" do
        # Collect from the same file twice
        signals = collector.collect([temp_file.path, temp_file.path])

        # Should not have duplicates
        signal_names = signals.map(&:name)
        expect(signal_names).to eq(signal_names.uniq)
      end
    end

    context "with file containing dynamic metrics" do
      let(:temp_file) do
        file = Tempfile.new(["test", ".rb"])
        file.write(<<~RUBY)
          class Service
            def track(metric_name)
              StatsD.increment(metric_name)  # Dynamic - can't be resolved
            end
          end
        RUBY
        file.close
        file
      end

      after { temp_file.unlink }

      it "tracks dynamic metrics separately" do
        collector.collect([temp_file.path])

        expect(collector.dynamic_metrics).not_to be_empty
        expect(collector.dynamic_metrics.first[:file]).to eq(temp_file.path)
      end

      it "includes metadata about dynamic metrics" do
        collector.collect([temp_file.path])

        metric = collector.dynamic_metrics.first
        expect(metric).to include(:file, :line, :type, :class, :receiver)
      end
    end

    context "with nonexistent files" do
      it "skips missing files gracefully" do
        signals = collector.collect(["/nonexistent/file.rb"])

        expect(signals).to be_empty
      end
    end

    context "with empty file list" do
      it "returns empty array" do
        signals = collector.collect([])

        expect(signals).to be_empty
      end
    end

    context "with mixed log and metric signals" do
      let(:temp_file) do
        file = Tempfile.new(["test", ".rb"])
        file.write(<<~RUBY)
          class MixedService
            def run
              logger.info "started"
              StatsD.increment("runs")
              Prometheus.gauge(:queue_size).set(10)
            end
          end
        RUBY
        file.close
        file
      end

      after { temp_file.unlink }

      it "collects both log and metric signals" do
        signals = collector.collect([temp_file.path])

        logs = signals.select(&:log?)
        metrics = signals.select(&:metric?)

        expect(logs).not_to be_empty
        expect(metrics).not_to be_empty
      end

      it "correctly types each signal" do
        signals = collector.collect([temp_file.path])

        signals.each do |signal|
          expect(signal).to respond_to(:log?, :metric?)
          expect([signal.log?, signal.metric?]).to include(true)
        end
      end
    end

    describe "architectural boundaries" do
      it "is a service that orchestrates detection" do
        # Should coordinate detectors and resolvers, not do low-level parsing
        expect(collector).not_to respond_to(:process)
        expect(collector).not_to respond_to(:parse)
        expect(collector).to respond_to(:collect)
      end

      it "returns domain objects (Signals), not hashes" do
        temp_file = Tempfile.new(["test", ".rb"])
        temp_file.write('class T; def m; logger.info "x"; end; end')
        temp_file.close

        signals = collector.collect([temp_file.path])

        temp_file.unlink

        expect(signals).to all(be_a(Grafantastic::Signal::Base))
      end
    end
  end
end
