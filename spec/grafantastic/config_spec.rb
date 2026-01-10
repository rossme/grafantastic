# frozen_string_literal: true

RSpec.describe Grafantastic::Config do
  subject(:config) { described_class.new }

  describe "guard rail limits" do
    it "has MAX_LOGS of 10" do
      expect(config.max_logs).to eq(10)
    end

    it "has MAX_METRICS of 10" do
      expect(config.max_metrics).to eq(10)
    end

    it "has MAX_EVENTS of 5" do
      expect(config.max_events).to eq(5)
    end

    it "has MAX_PANELS of 12" do
      expect(config.max_panels).to eq(12)
    end
  end

  describe "#grafana_url" do
    it "reads from GRAFANA_URL environment variable" do
      allow(ENV).to receive(:[]).with("GRAFANA_URL").and_return("https://grafana.example.com")
      expect(config.grafana_url).to eq("https://grafana.example.com")
    end

    it "returns nil when not set" do
      allow(ENV).to receive(:[]).with("GRAFANA_URL").and_return(nil)
      expect(config.grafana_url).to be_nil
    end
  end

  describe "#grafana_token" do
    it "reads from GRAFANA_TOKEN environment variable" do
      allow(ENV).to receive(:[]).with("GRAFANA_TOKEN").and_return("secret-token")
      expect(config.grafana_token).to eq("secret-token")
    end
  end

  describe "#grafana_folder_id" do
    it "reads from GRAFANA_FOLDER_ID environment variable" do
      allow(ENV).to receive(:[]).with("GRAFANA_FOLDER_ID").and_return("123")
      expect(config.grafana_folder_id).to eq("123")
    end
  end

  describe "#dry_run?" do
    it "returns true when GRAFANTASTIC_DRY_RUN is 'true'" do
      allow(ENV).to receive(:[]).with("GRAFANTASTIC_DRY_RUN").and_return("true")
      expect(config.dry_run?).to be true
    end

    it "returns false when GRAFANTASTIC_DRY_RUN is not 'true'" do
      allow(ENV).to receive(:[]).with("GRAFANTASTIC_DRY_RUN").and_return("false")
      expect(config.dry_run?).to be false
    end

    it "returns false when GRAFANTASTIC_DRY_RUN is not set" do
      allow(ENV).to receive(:[]).with("GRAFANTASTIC_DRY_RUN").and_return(nil)
      expect(config.dry_run?).to be false
    end
  end
end
