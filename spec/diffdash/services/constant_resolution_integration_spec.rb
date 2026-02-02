# frozen_string_literal: true

RSpec.describe 'Constant Resolution Integration' do
  let(:temp_dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(temp_dir) }

  def create_file(name, content)
    path = File.join(temp_dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  describe 'detecting metrics via constant resolution' do
    it 'resolves Metrics::RequestTotal.increment to the metric name' do
      # Create metrics definition file
      create_file('app/services/metrics.rb', <<~RUBY)
        module Metrics
          RequestTotal = Hesiod.register_counter("request_total")
          QueueDepth = Hesiod.register_gauge("queue_depth")
        end
      RUBY

      # Create file using the constants
      worker_path = create_file('app/jobs/worker.rb', <<~RUBY)
        class Worker
          def perform
            Metrics::RequestTotal.increment
            Metrics::QueueDepth.set(5)
          end
        end
      RUBY

      # Initialize git repo so SignalCollector can find root
      Dir.chdir(temp_dir) do
        system('git init -q')
        system('git add -A')
        system("git commit -q -m 'init'")
      end

      collector = Diffdash::Services::SignalCollector.new
      signals = collector.collect([worker_path])

      metric_names = signals.select { |s| s.type == :metric }.map(&:name)
      expect(metric_names).to contain_exactly('request_total', 'queue_depth')
    end

    it 'detects metric types correctly' do
      create_file('app/services/metrics.rb', <<~RUBY)
        module Metrics
          Counter1 = Hesiod.register_counter("counter_metric")
          Gauge1 = Hesiod.register_gauge("gauge_metric")
          Histogram1 = Hesiod.register_histogram("histogram_metric")
        end
      RUBY

      worker_path = create_file('app/jobs/worker.rb', <<~RUBY)
        class Worker
          def perform
            Metrics::Counter1.increment
            Metrics::Gauge1.set(10)
            Metrics::Histogram1.observe(1.5)
          end
        end
      RUBY

      Dir.chdir(temp_dir) do
        system('git init -q')
        system('git add -A')
        system("git commit -q -m 'init'")
      end

      collector = Diffdash::Services::SignalCollector.new
      signals = collector.collect([worker_path])

      metrics = signals.select { |s| s.type == :metric }

      counter = metrics.find { |m| m.name == 'counter_metric' }
      gauge = metrics.find { |m| m.name == 'gauge_metric' }
      histogram = metrics.find { |m| m.name == 'histogram_metric' }

      expect(counter).to be_a(Diffdash::Signal::Counter)
      expect(gauge).to be_a(Diffdash::Signal::Gauge)
      expect(histogram).to be_a(Diffdash::Signal::Histogram)
    end

    it 'still detects inline Hesiod calls' do
      worker_path = create_file('app/jobs/worker.rb', <<~RUBY)
        class Worker
          def perform
            Hesiod.emit("inline_counter")
            Hesiod.gauge("inline_gauge", 5)
          end
        end
      RUBY

      Dir.chdir(temp_dir) do
        system('git init -q')
        system('git add -A')
        system("git commit -q -m 'init'")
      end

      collector = Diffdash::Services::SignalCollector.new
      signals = collector.collect([worker_path])

      metric_names = signals.select { |s| s.type == :metric }.map(&:name)
      expect(metric_names).to contain_exactly('inline_counter', 'inline_gauge')
    end
  end
end
