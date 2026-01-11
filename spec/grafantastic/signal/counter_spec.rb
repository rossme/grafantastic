# frozen_string_literal: true

RSpec.describe Grafantastic::Signal::Counter do
  subject(:counter_signal) do
    described_class.new(
      name: "requests_total",
      source_file: "/app/controllers/api.rb",
      defining_class: "ApiController",
      inheritance_depth: 0,
      metadata: { line: 15 }
    )
  end

  describe "#initialize" do
    it "sets all attributes with type :metric" do
      expect(counter_signal.name).to eq("requests_total")
      expect(counter_signal.type).to eq(:metric)
      expect(counter_signal.source_file).to eq("/app/controllers/api.rb")
      expect(counter_signal.defining_class).to eq("ApiController")
      expect(counter_signal.metadata[:metric_type]).to eq(:counter)
      expect(counter_signal.metadata[:line]).to eq(15)
    end
  end

  describe "#metric?" do
    it "returns true" do
      expect(counter_signal.metric?).to be true
    end
  end

  describe "#log?" do
    it "returns false" do
      expect(counter_signal.log?).to be false
    end
  end

  describe "#to_h" do
    it "includes metric_type in metadata for backward compatibility" do
      hash = counter_signal.to_h
      expect(hash[:type]).to eq(:metric)
      expect(hash[:metadata][:metric_type]).to eq(:counter)
    end
  end
end
