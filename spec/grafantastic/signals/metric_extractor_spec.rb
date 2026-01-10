# frozen_string_literal: true

RSpec.describe Grafantastic::Signals::MetricExtractor do
  let(:file_path) { "/app/services/payment.rb" }

  def create_visitor_with_metrics(metric_calls)
    instance_double(
      Grafantastic::AST::Visitor,
      file_path: file_path,
      inheritance_depth: 0,
      metric_calls: metric_calls
    )
  end

  describe ".extract" do
    it "creates Signal objects from metric calls" do
      visitor = create_visitor_with_metrics([
        { name: "payments_total", metric_type: :counter, defining_class: "PaymentProcessor", line: 10 }
      ])

      signals = described_class.extract(visitor)

      expect(signals.size).to eq(1)
      expect(signals.first).to be_a(Grafantastic::Signals::Signal)
      expect(signals.first.type).to eq(:metric)
      expect(signals.first.name).to eq("payments_total")
    end

    it "preserves metric type in metadata" do
      visitor = create_visitor_with_metrics([
        { name: "request_duration", metric_type: :histogram, defining_class: "Test", line: 10 }
      ])

      signals = described_class.extract(visitor)

      expect(signals.first.metadata[:metric_type]).to eq(:histogram)
    end

    it "preserves line number in metadata" do
      visitor = create_visitor_with_metrics([
        { name: "test_metric", metric_type: :counter, defining_class: "Test", line: 42 }
      ])

      signals = described_class.extract(visitor)

      expect(signals.first.metadata[:line]).to eq(42)
    end

    it "preserves inheritance depth from visitor" do
      visitor = instance_double(
        Grafantastic::AST::Visitor,
        file_path: file_path,
        inheritance_depth: 1,
        metric_calls: [{ name: "test", metric_type: :counter, defining_class: "Base", line: 5 }]
      )

      signals = described_class.extract(visitor)

      expect(signals.first.inheritance_depth).to eq(1)
    end

    it "skips metric calls with nil name" do
      visitor = create_visitor_with_metrics([
        { name: nil, metric_type: :counter, defining_class: "Test", line: 10 },
        { name: "valid_metric", metric_type: :counter, defining_class: "Test", line: 20 }
      ])

      signals = described_class.extract(visitor)

      expect(signals.size).to eq(1)
      expect(signals.first.name).to eq("valid_metric")
    end

    it "extracts multiple metric signals" do
      visitor = create_visitor_with_metrics([
        { name: "requests_total", metric_type: :counter, defining_class: "Test", line: 1 },
        { name: "request_duration", metric_type: :histogram, defining_class: "Test", line: 2 },
        { name: "queue_size", metric_type: :gauge, defining_class: "Test", line: 3 }
      ])

      signals = described_class.extract(visitor)

      expect(signals.size).to eq(3)
      expect(signals.map(&:name)).to eq(%w[requests_total request_duration queue_size])
    end

    it "returns empty array for visitor with no metric calls" do
      visitor = create_visitor_with_metrics([])

      signals = described_class.extract(visitor)

      expect(signals).to eq([])
    end
  end
end
