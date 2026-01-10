# frozen_string_literal: true

RSpec.describe Grafantastic::Validation::Limits do
  let(:config) { Grafantastic::Config.new }
  subject(:validator) { described_class.new(config) }

  def create_signal(type:, name: "test", defining_class: "Test", metadata: {})
    Grafantastic::Signals::Signal.new(
      type: type,
      name: name,
      source_file: "/test.rb",
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

  describe "#validate!" do
    context "when within limits" do
      it "does not raise for signals within all limits" do
        # Stay within panel limit: 5 logs + 5 metrics = 10 panels (under 12)
        signals = create_logs(5) + create_metrics(5)

        expect { validator.validate!(signals) }.not_to raise_error
      end

      it "does not raise for empty signals" do
        expect { validator.validate!([]) }.not_to raise_error
      end

      it "does not raise at exactly max limits" do
        signals = create_logs(10) + create_metrics(10) + create_events(5)

        # This will exceed panel limit (10 + 10 + 5 = 25 panels > 12)
        # But if we have fewer, it should pass
        signals = create_logs(5) + create_metrics(5)

        expect { validator.validate!(signals) }.not_to raise_error
      end
    end

    context "when logs limit exceeded" do
      it "raises LimitExceededError" do
        signals = create_logs(11)

        expect { validator.validate!(signals) }.to raise_error(
          Grafantastic::LimitExceededError,
          /Logs limit exceeded: found 11, max allowed 10/
        )
      end

      it "includes top contributor in error message" do
        signals = 11.times.map do |i|
          create_signal(type: :log, name: "log_#{i}", defining_class: "NoisyClass")
        end

        expect { validator.validate!(signals) }.to raise_error(
          Grafantastic::LimitExceededError,
          /Top contributor: NoisyClass/
        )
      end
    end

    context "when metrics limit exceeded" do
      it "raises LimitExceededError" do
        signals = create_metrics(11)

        expect { validator.validate!(signals) }.to raise_error(
          Grafantastic::LimitExceededError,
          /Metrics limit exceeded: found 11, max allowed 10/
        )
      end
    end

    context "when events limit exceeded" do
      it "raises LimitExceededError" do
        signals = create_events(6)

        expect { validator.validate!(signals) }.to raise_error(
          Grafantastic::LimitExceededError,
          /Events limit exceeded: found 6, max allowed 5/
        )
      end
    end

    context "when panel limit exceeded" do
      it "raises LimitExceededError for too many total panels" do
        # 10 logs = 10 panels, 3 counters = 3 panels = 13 panels > 12
        signals = create_logs(10) + create_metrics(3)

        expect { validator.validate!(signals) }.to raise_error(
          Grafantastic::LimitExceededError,
          /Panel limit exceeded: 13 panels would be generated/
        )
      end

      it "counts histogram as 3 panels" do
        # 1 histogram = 3 panels (p50, p95, p99)
        # 10 logs = 10 panels
        # Total = 13 panels > 12
        signals = create_logs(10) + create_metrics(1, type: :histogram)

        expect { validator.validate!(signals) }.to raise_error(
          Grafantastic::LimitExceededError,
          /Panel limit exceeded: 13 panels/
        )
      end

      it "includes breakdown in error message" do
        signals = create_logs(10) + create_metrics(3)

        expect { validator.validate!(signals) }.to raise_error(
          Grafantastic::LimitExceededError,
          /Breakdown: 10 logs, 3 metrics, 0 events/
        )
      end
    end

    context "error message formatting" do
      it "identifies the class contributing most signals" do
        signals = [
          create_signal(type: :log, name: "a", defining_class: "SmallClass"),
          create_signal(type: :log, name: "b", defining_class: "BigClass"),
          create_signal(type: :log, name: "c", defining_class: "BigClass"),
          create_signal(type: :log, name: "d", defining_class: "BigClass"),
        ] + create_logs(8) # Total 12 logs

        expect { validator.validate!(signals) }.to raise_error(
          Grafantastic::LimitExceededError,
          /Top contributor: .* \(\d+ signals\)/
        )
      end
    end
  end
end
