# frozen_string_literal: true

RSpec.describe Grafantastic::Signals::Signal do
  subject(:signal) do
    described_class.new(
      type: :log,
      name: "payment_processed",
      source_file: "/app/services/payment.rb",
      defining_class: "PaymentProcessor",
      inheritance_depth: 0,
      metadata: { level: "info", line: 42 }
    )
  end

  describe "#initialize" do
    it "sets all attributes" do
      expect(signal.type).to eq(:log)
      expect(signal.name).to eq("payment_processed")
      expect(signal.source_file).to eq("/app/services/payment.rb")
      expect(signal.defining_class).to eq("PaymentProcessor")
      expect(signal.inheritance_depth).to eq(0)
      expect(signal.metadata).to eq({ level: "info", line: 42 })
    end

    it "defaults metadata to empty hash" do
      signal = described_class.new(
        type: :log,
        name: "test",
        source_file: "/test.rb",
        defining_class: "Test",
        inheritance_depth: 0
      )

      expect(signal.metadata).to eq({})
    end
  end

  describe "#log?" do
    it "returns true for log type" do
      expect(signal.log?).to be true
    end

    it "returns false for other types" do
      metric = described_class.new(
        type: :metric,
        name: "test",
        source_file: "/test.rb",
        defining_class: "Test",
        inheritance_depth: 0
      )

      expect(metric.log?).to be false
    end
  end

  describe "#metric?" do
    it "returns true for metric type" do
      metric = described_class.new(
        type: :metric,
        name: "requests_total",
        source_file: "/test.rb",
        defining_class: "Test",
        inheritance_depth: 0
      )

      expect(metric.metric?).to be true
    end

    it "returns false for other types" do
      expect(signal.metric?).to be false
    end
  end

  describe "#event?" do
    it "returns true for event type" do
      event = described_class.new(
        type: :event,
        name: "user_signed_up",
        source_file: "/test.rb",
        defining_class: "Test",
        inheritance_depth: 0
      )

      expect(event.event?).to be true
    end

    it "returns false for other types" do
      expect(signal.event?).to be false
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      expect(signal.to_h).to eq({
        type: :log,
        name: "payment_processed",
        source_file: "/app/services/payment.rb",
        defining_class: "PaymentProcessor",
        inheritance_depth: 0,
        metadata: { level: "info", line: 42 }
      })
    end
  end
end
