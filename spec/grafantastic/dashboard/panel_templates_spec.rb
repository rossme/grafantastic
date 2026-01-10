# frozen_string_literal: true

RSpec.describe Grafantastic::Dashboard::PanelTemplates do
  def create_signal(type:, name:, metadata: {})
    Grafantastic::Signals::Signal.new(
      type: type,
      name: name,
      source_file: "/app/services/payment.rb",
      defining_class: "PaymentProcessor",
      inheritance_depth: 0,
      metadata: metadata
    )
  end

  describe ".log_panel" do
    let(:signal) { create_signal(type: :log, name: "payment_processed", metadata: { level: "info" }) }
    let(:panel) { described_class.log_panel(signal, 1, { x: 0, y: 0, w: 12, h: 8 }) }

    it "creates a logs panel type" do
      expect(panel[:type]).to eq("logs")
    end

    it "sets panel id" do
      expect(panel[:id]).to eq(1)
    end

    it "includes signal name in title" do
      expect(panel[:title]).to include("payment_processed")
    end

    it "includes source class in description" do
      expect(panel[:description]).to include("PaymentProcessor")
    end

    it "sets grid position" do
      expect(panel[:gridPos]).to eq({ x: 0, y: 0, w: 12, h: 8 })
    end

    it "uses Loki datasource" do
      expect(panel[:targets].first[:datasource][:type]).to eq("loki")
      expect(panel[:targets].first[:datasource][:uid]).to eq("${datasource_loki}")
    end

    it "includes event name in query" do
      expect(panel[:targets].first[:expr]).to include("payment_processed")
    end

    it "uses templated variables in query" do
      expect(panel[:targets].first[:expr]).to include("$service")
      expect(panel[:targets].first[:expr]).to include("$env")
    end

    it "truncates long names" do
      long_signal = create_signal(type: :log, name: "a" * 50)
      panel = described_class.log_panel(long_signal, 1, { x: 0, y: 0, w: 12, h: 8 })

      expect(panel[:title].length).to be <= 40
    end
  end

  describe ".counter_panel" do
    let(:signal) { create_signal(type: :metric, name: "payments_total", metadata: { metric_type: :counter }) }
    let(:panel) { described_class.counter_panel(signal, 1, { x: 0, y: 0, w: 8, h: 8 }) }

    it "creates a timeseries panel type" do
      expect(panel[:type]).to eq("timeseries")
    end

    it "includes metric name in title" do
      expect(panel[:title]).to include("payments_total")
    end

    it "uses Prometheus datasource" do
      expect(panel[:targets].first[:datasource][:type]).to eq("prometheus")
      expect(panel[:targets].first[:datasource][:uid]).to eq("${datasource}")
    end

    it "uses rate query for counters" do
      expect(panel[:targets].first[:expr]).to include("rate(")
      expect(panel[:targets].first[:expr]).to include("$__rate_interval")
    end

    it "sets unit to ops" do
      expect(panel[:fieldConfig][:defaults][:unit]).to eq("ops")
    end

    it "sanitizes metric name in query" do
      signal_with_dots = create_signal(type: :metric, name: "payments.processed.total")
      panel = described_class.counter_panel(signal_with_dots, 1, { x: 0, y: 0, w: 8, h: 8 })

      expect(panel[:targets].first[:expr]).to include("payments_processed_total")
    end
  end

  describe ".gauge_panel" do
    let(:signal) { create_signal(type: :metric, name: "queue_size", metadata: { metric_type: :gauge }) }
    let(:panel) { described_class.gauge_panel(signal, 1, { x: 0, y: 0, w: 8, h: 8 }) }

    it "creates a timeseries panel type" do
      expect(panel[:type]).to eq("timeseries")
    end

    it "includes metric name in title" do
      expect(panel[:title]).to include("queue_size")
    end

    it "does not use rate in query" do
      expect(panel[:targets].first[:expr]).not_to include("rate(")
    end

    it "uses templated service and env variables" do
      expect(panel[:targets].first[:expr]).to include("$service")
      expect(panel[:targets].first[:expr]).to include("$env")
    end
  end

  describe ".histogram_panels" do
    let(:signal) { create_signal(type: :metric, name: "request_duration", metadata: { metric_type: :histogram }) }
    let(:panels) { described_class.histogram_panels(signal, 1, { x: 0, y: 0, w: 8, h: 8 }) }

    it "creates 3 panels for p50, p95, p99" do
      expect(panels.size).to eq(3)
    end

    it "assigns sequential panel ids" do
      expect(panels.map { |p| p[:id] }).to eq([1, 2, 3])
    end

    it "includes percentile in title" do
      titles = panels.map { |p| p[:title] }
      expect(titles).to include(a_string_including("p50"))
      expect(titles).to include(a_string_including("p95"))
      expect(titles).to include(a_string_including("p99"))
    end

    it "uses histogram_quantile in queries" do
      panels.each do |panel|
        expect(panel[:targets].first[:expr]).to include("histogram_quantile")
      end
    end

    it "queries _bucket suffix" do
      panels.each do |panel|
        expect(panel[:targets].first[:expr]).to include("request_duration_bucket")
      end
    end

    it "sets unit to seconds" do
      panels.each do |panel|
        expect(panel[:fieldConfig][:defaults][:unit]).to eq("s")
      end
    end

    it "uses correct quantile values" do
      exprs = panels.map { |p| p[:targets].first[:expr] }
      expect(exprs[0]).to include("0.5")
      expect(exprs[1]).to include("0.95")
      expect(exprs[2]).to include("0.99")
    end
  end

  describe ".empty_dashboard_panel" do
    let(:panel) { described_class.empty_dashboard_panel }

    it "creates a text panel" do
      expect(panel[:type]).to eq("text")
    end

    it "has id of 1" do
      expect(panel[:id]).to eq(1)
    end

    it "spans full width" do
      expect(panel[:gridPos][:w]).to eq(24)
    end

    it "includes message about no signals" do
      expect(panel[:options][:content]).to include("No observability signals detected")
    end

    it "uses markdown mode" do
      expect(panel[:options][:mode]).to eq("markdown")
    end
  end
end
