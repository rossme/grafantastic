# frozen_string_literal: true

RSpec.describe Grafantastic::Dashboard::Builder do
  let(:config) { Grafantastic::Config.new }

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

  describe "#build" do
    context "with signals" do
      let(:signals) do
        [
          create_signal(type: :log, name: "payment_started", metadata: { level: "info" }),
          create_signal(type: :metric, name: "payments_total", metadata: { metric_type: :counter })
        ]
      end

      subject(:builder) { described_class.new(title: "feature-branch", signals: signals, config: config) }
      let(:result) { builder.build }

      it "returns hash with dashboard key" do
        expect(result).to have_key(:dashboard)
      end

      it "sets overwrite to true" do
        expect(result[:overwrite]).to be true
      end

      it "includes auto-generated message" do
        expect(result[:message]).to include("grafantastic")
      end

      describe "dashboard structure" do
        let(:dashboard) { result[:dashboard] }

        it "sets title from builder" do
          expect(dashboard[:title]).to eq("feature-branch")
        end

        it "generates deterministic uid from title" do
          expect(dashboard[:uid]).to be_a(String)
          expect(dashboard[:uid].length).to eq(12)

          # Same title should produce same uid
          other_builder = described_class.new(title: "feature-branch", signals: signals, config: config)
          expect(other_builder.build[:dashboard][:uid]).to eq(dashboard[:uid])
        end

        it "includes grafantastic tag" do
          expect(dashboard[:tags]).to include("grafantastic")
        end

        it "includes auto-pr tag" do
          expect(dashboard[:tags]).to include("auto-pr")
        end

        it "sets schema version" do
          expect(dashboard[:schemaVersion]).to eq(39)
        end

        it "sets relative time range" do
          expect(dashboard[:time][:from]).to eq("now-1h")
          expect(dashboard[:time][:to]).to eq("now")
        end

        it "sets refresh interval" do
          expect(dashboard[:refresh]).to eq("30s")
        end
      end

      describe "templating" do
        let(:templating) { result[:dashboard][:templating][:list] }

        it "includes datasource variable" do
          ds = templating.find { |t| t[:name] == "datasource" }
          expect(ds[:type]).to eq("datasource")
          expect(ds[:query]).to eq("prometheus")
        end

        it "includes loki datasource variable" do
          ds = templating.find { |t| t[:name] == "datasource_loki" }
          expect(ds[:type]).to eq("datasource")
          expect(ds[:query]).to eq("loki")
        end

        it "includes service variable" do
          svc = templating.find { |t| t[:name] == "service" }
          expect(svc[:type]).to eq("query")
        end

        it "includes env variable" do
          env = templating.find { |t| t[:name] == "env" }
          expect(env[:type]).to eq("custom")
          expect(env[:query]).to include("production")
        end
      end

      describe "panels" do
        let(:panels) { result[:dashboard][:panels] }

        it "creates panels for each signal" do
          expect(panels.size).to eq(2)
        end

        it "creates log panel for log signal" do
          log_panel = panels.find { |p| p[:type] == "logs" }
          expect(log_panel).not_to be_nil
          expect(log_panel[:title]).to include("payment_started")
        end

        it "creates timeseries panel for counter signal" do
          counter_panel = panels.find { |p| p[:type] == "timeseries" }
          expect(counter_panel).not_to be_nil
          expect(counter_panel[:title]).to include("payments_total")
        end

        it "assigns unique panel ids" do
          ids = panels.map { |p| p[:id] }
          expect(ids.uniq.size).to eq(ids.size)
        end
      end

      describe "annotations" do
        let(:annotations) { result[:dashboard][:annotations][:list] }

        it "includes deployment annotation" do
          deploy = annotations.find { |a| a[:name] == "Deployments" }
          expect(deploy).not_to be_nil
          expect(deploy[:enable]).to be true
        end
      end
    end

    context "with histogram signals" do
      let(:signals) do
        [create_signal(type: :metric, name: "request_duration", metadata: { metric_type: :histogram })]
      end

      subject(:builder) { described_class.new(title: "test", signals: signals, config: config) }

      it "creates 3 panels for histogram (p50, p95, p99)" do
        panels = builder.build[:dashboard][:panels]
        expect(panels.size).to eq(3)
      end
    end

    context "with no signals" do
      subject(:builder) { described_class.new(title: "empty-pr", signals: [], config: config) }

      it "creates single text panel" do
        panels = builder.build[:dashboard][:panels]
        expect(panels.size).to eq(1)
        expect(panels.first[:type]).to eq("text")
      end

      it "includes 'no signals' message" do
        panel = builder.build[:dashboard][:panels].first
        expect(panel[:options][:content]).to include("No observability signals detected")
      end
    end

    context "with folder id configured" do
      before do
        allow(config).to receive(:grafana_folder_id).and_return("123")
      end

      subject(:builder) { described_class.new(title: "test", signals: [], config: config) }

      it "includes folder id as integer" do
        expect(builder.build[:folderId]).to eq(123)
      end
    end

    context "without folder id" do
      subject(:builder) { described_class.new(title: "test", signals: [], config: config) }

      it "sets folder id to nil" do
        expect(builder.build[:folderId]).to be_nil
      end
    end
  end
end
