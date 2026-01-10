# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Grafantastic::Configuration do
  let(:temp_dir) { Dir.mktmpdir }
  let(:global_config_path) { File.join(temp_dir, ".grafantastic.yml") }
  let(:local_config_path) { File.join(temp_dir, "project", ".grafantastic.yml") }

  before do
    FileUtils.mkdir_p(File.join(temp_dir, "project"))
    stub_const("Grafantastic::Configuration::GLOBAL_CONFIG_PATH", global_config_path)
    allow(Dir).to receive(:pwd).and_return(File.join(temp_dir, "project"))
    # Clear ENV for tests
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GRAFANA_URL").and_return(nil)
    allow(ENV).to receive(:[]).with("GRAFANA_TOKEN").and_return(nil)
    allow(ENV).to receive(:[]).with("GRAFANA_FOLDER_ID").and_return(nil)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#load_config" do
    it "loads from global config file" do
      File.write(global_config_path, YAML.dump({
        "grafana_url" => "https://global.grafana.net",
        "grafana_token" => "global_token"
      }))

      config = described_class.new

      expect(config.grafana_url).to eq("https://global.grafana.net")
      expect(config.grafana_token).to eq("global_token")
    end

    it "local config overrides global config" do
      File.write(global_config_path, YAML.dump({
        "grafana_url" => "https://global.grafana.net",
        "grafana_token" => "global_token"
      }))
      File.write(local_config_path, YAML.dump({
        "grafana_url" => "https://local.grafana.net"
      }))

      config = described_class.new

      expect(config.grafana_url).to eq("https://local.grafana.net")
      expect(config.grafana_token).to eq("global_token")
    end

    it "ENV overrides config files" do
      File.write(global_config_path, YAML.dump({
        "grafana_url" => "https://global.grafana.net"
      }))
      allow(ENV).to receive(:[]).with("GRAFANA_URL").and_return("https://env.grafana.net")

      config = described_class.new

      expect(config.grafana_url).to eq("https://env.grafana.net")
    end
  end

  describe "#save" do
    it "saves to local config by default" do
      config = described_class.new
      config.save("grafana_url", "https://test.grafana.net")

      saved = YAML.safe_load(File.read(local_config_path))
      expect(saved["grafana_url"]).to eq("https://test.grafana.net")
    end

    it "saves to global config with global: true" do
      config = described_class.new
      config.save("grafana_url", "https://test.grafana.net", global: true)

      saved = YAML.safe_load(File.read(global_config_path))
      expect(saved["grafana_url"]).to eq("https://test.grafana.net")
    end

    it "raises on invalid key" do
      config = described_class.new

      expect {
        config.save("invalid_key", "value")
      }.to raise_error(ArgumentError, /Invalid config key/)
    end
  end

  describe "#delete" do
    it "removes key from config file" do
      File.write(local_config_path, YAML.dump({
        "grafana_url" => "https://test.grafana.net",
        "grafana_folder_id" => "123"
      }))

      config = described_class.new
      config.delete("grafana_folder_id")

      saved = YAML.safe_load(File.read(local_config_path))
      expect(saved).not_to have_key("grafana_folder_id")
      expect(saved["grafana_url"]).to eq("https://test.grafana.net")
    end
  end

  describe "#show" do
    it "returns all config values with token redacted" do
      File.write(global_config_path, YAML.dump({
        "grafana_url" => "https://test.grafana.net",
        "grafana_token" => "secret_token",
        "grafana_folder_id" => "42"
      }))

      config = described_class.new

      expect(config.show).to eq({
        "grafana_url" => "https://test.grafana.net",
        "grafana_token" => "[REDACTED]",
        "grafana_folder_id" => "42"
      })
    end
  end

  describe "#configured?" do
    it "returns true when url and token are set" do
      File.write(global_config_path, YAML.dump({
        "grafana_url" => "https://test.grafana.net",
        "grafana_token" => "token"
      }))

      config = described_class.new

      expect(config.configured?).to be true
    end

    it "returns false when url is missing" do
      File.write(global_config_path, YAML.dump({
        "grafana_token" => "token"
      }))

      config = described_class.new

      expect(config.configured?).to be false
    end
  end
end
