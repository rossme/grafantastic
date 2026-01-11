# frozen_string_literal: true

RSpec.describe Grafantastic::Signals::LogExtractor do
  let(:file_path) { "/app/services/payment.rb" }

  def create_visitor_with_logs(log_calls)
    visitor = instance_double(
      Grafantastic::AST::Visitor,
      file_path: file_path,
      inheritance_depth: 0,
      log_calls: log_calls
    )
    visitor
  end

  describe ".extract" do
    it "creates Signal objects from log calls" do
      visitor = create_visitor_with_logs([
        { level: "info", event_name: "payment_processed", defining_class: "PaymentProcessor", line: 10 }
      ])

      signals = described_class.extract(visitor)

      expect(signals.size).to eq(1)
      # New typed signals - Log
      expect(signals.first).to respond_to(:type, :name, :metadata)
      expect(signals.first.type).to eq(:log)
      expect(signals.first.name).to eq("payment_processed")
    end

    it "preserves log level in metadata" do
      visitor = create_visitor_with_logs([
        { level: "error", event_name: "payment_failed", defining_class: "PaymentProcessor", line: 10 }
      ])

      signals = described_class.extract(visitor)

      expect(signals.first.metadata[:level]).to eq("error")
    end

    it "preserves line number in metadata" do
      visitor = create_visitor_with_logs([
        { level: "info", event_name: "test", defining_class: "Test", line: 42 }
      ])

      signals = described_class.extract(visitor)

      expect(signals.first.metadata[:line]).to eq(42)
    end

    it "preserves inheritance depth from visitor" do
      visitor = instance_double(
        Grafantastic::AST::Visitor,
        file_path: file_path,
        inheritance_depth: 1,
        log_calls: [{ level: "info", event_name: "test", defining_class: "Base", line: 5 }]
      )

      signals = described_class.extract(visitor)

      expect(signals.first.inheritance_depth).to eq(1)
    end

    it "generates fallback name when event_name is nil" do
      visitor = create_visitor_with_logs([
        { level: "info", event_name: nil, defining_class: "PaymentProcessor", line: 10 }
      ])

      signals = described_class.extract(visitor)

      expect(signals.first.name).to match(/^log_[a-f0-9]{8}$/)
    end

    it "extracts multiple log signals" do
      visitor = create_visitor_with_logs([
        { level: "info", event_name: "start", defining_class: "Test", line: 1 },
        { level: "warn", event_name: "warning", defining_class: "Test", line: 2 },
        { level: "error", event_name: "failed", defining_class: "Test", line: 3 }
      ])

      signals = described_class.extract(visitor)

      expect(signals.size).to eq(3)
      expect(signals.map(&:name)).to eq(%w[start warning failed])
    end

    it "returns empty array for visitor with no log calls" do
      visitor = create_visitor_with_logs([])

      signals = described_class.extract(visitor)

      expect(signals).to eq([])
    end
  end
end
