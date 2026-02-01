# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "tmpdir"

RSpec.describe Diffdash::ConfigLoader do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  def create_config_file(content, filename: "diffdash.yml", dir: temp_dir)
    path = File.join(dir, filename)
    File.write(path, content)
    path
  end

  describe "file discovery" do
    it "finds diffdash.yml in the working directory" do
      create_config_file("default_env: staging")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.loaded_from).to eq(File.join(temp_dir, "diffdash.yml"))
    end

    it "finds diffdash.yaml as an alternative extension" do
      create_config_file("default_env: staging", filename: "diffdash.yaml")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.loaded_from).to eq(File.join(temp_dir, "diffdash.yaml"))
    end

    it "finds .diffdash.yml (hidden file)" do
      create_config_file("default_env: staging", filename: ".diffdash.yml")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.loaded_from).to eq(File.join(temp_dir, ".diffdash.yml"))
    end

    it "prefers diffdash.yml over .diffdash.yml" do
      create_config_file("default_env: one", filename: "diffdash.yml")
      create_config_file("default_env: two", filename: ".diffdash.yml")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.loaded_from).to eq(File.join(temp_dir, "diffdash.yml"))
      expect(loader.default_env).to eq("one")
    end

    it "uses explicit config_path when provided" do
      custom_path = create_config_file("default_env: custom", filename: "custom.yml")
      loader = described_class.new(config_path: custom_path)
      expect(loader.loaded_from).to eq(custom_path)
      expect(loader.default_env).to eq("custom")
    end

    it "warns when explicit config_path does not exist" do
      expect do
        described_class.new(config_path: "/nonexistent/config.yml")
      end.to output(/Warning: Config file not found/).to_stderr
    end

    it "returns nil for loaded_from when no config file is found" do
      empty_dir = Dir.mktmpdir
      loader = described_class.new(working_dir: empty_dir)
      expect(loader.loaded_from).to be_nil
      FileUtils.remove_entry(empty_dir)
    end
  end

  describe "grafana configuration" do
    it "loads grafana.url from config file" do
      create_config_file(<<~YAML)
        grafana:
          url: https://grafana.example.com
      YAML
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.grafana_url).to eq("https://grafana.example.com")
    end

    it "loads grafana.folder_id from config file" do
      create_config_file(<<~YAML)
        grafana:
          folder_id: 42
      YAML
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.grafana_folder_id).to eq("42")
    end

    it "prioritizes DIFFDASH_GRAFANA_URL over file config" do
      create_config_file(<<~YAML)
        grafana:
          url: https://file.example.com
      YAML
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DIFFDASH_GRAFANA_URL").and_return("https://env.example.com")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.grafana_url).to eq("https://env.example.com")
    end

    it "only allows grafana_token from environment variables (security)" do
      create_config_file(<<~YAML)
        grafana:
          token: should-be-ignored
      YAML
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DIFFDASH_GRAFANA_TOKEN").and_return(nil)
      allow(ENV).to receive(:[]).with("GRAFANA_TOKEN").and_return(nil)
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.grafana_token).to be_nil
    end
  end

  describe "outputs configuration" do
    it "loads outputs array from config file" do
      create_config_file(<<~YAML)
        outputs:
          - grafana
          - json
      YAML
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.outputs).to eq([:grafana, :json])
    end

    it "returns empty array when not configured" do
      create_config_file("")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.outputs).to eq([])
    end

    it "prioritizes DIFFDASH_OUTPUTS env var over file config" do
      create_config_file(<<~YAML)
        outputs:
          - grafana
      YAML
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DIFFDASH_OUTPUTS").and_return("json")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.outputs).to eq([:json])
    end
  end

  describe "general settings" do
    it "loads default_env from config file" do
      create_config_file("default_env: staging")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.default_env).to eq("staging")
    end

    it "defaults default_env to 'production'" do
      create_config_file("")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.default_env).to eq("production")
    end

    it "loads pr_comment from config file" do
      create_config_file("pr_comment: false")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.pr_comment?).to be false
    end

    it "defaults pr_comment to true" do
      create_config_file("")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.pr_comment?).to be true
    end

    it "loads app_name from config file" do
      create_config_file("app_name: my-service")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.app_name).to eq("my-service")
    end

    it "loads pr_deploy_annotation_expr from config file" do
      create_config_file('pr_deploy_annotation_expr: changes(deploy_ts[5m]) > 0')
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.pr_deploy_annotation_expr).to eq("changes(deploy_ts[5m]) > 0")
    end
  end

  describe "file filtering configuration" do
    it "loads ignore_paths from config file" do
      create_config_file(<<~YAML)
        ignore_paths:
          - vendor/
          - lib/legacy/
      YAML
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.ignore_paths).to eq(["vendor/", "lib/legacy/"])
    end

    it "defaults ignore_paths to empty array" do
      create_config_file("")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.ignore_paths).to eq([])
    end

    it "loads include_paths from config file" do
      create_config_file(<<~YAML)
        include_paths:
          - app/
          - lib/
      YAML
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.include_paths).to eq(["app/", "lib/"])
    end

    it "loads excluded_suffixes from config file" do
      create_config_file(<<~YAML)
        excluded_suffixes:
          - _spec.rb
          - _integration.rb
      YAML
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.excluded_suffixes).to eq(["_spec.rb", "_integration.rb"])
    end

    it "defaults excluded_suffixes to _spec.rb and _test.rb" do
      create_config_file("")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.excluded_suffixes).to eq(%w[_spec.rb _test.rb])
    end

    it "loads excluded_directories from config file" do
      create_config_file(<<~YAML)
        excluded_directories:
          - spec
          - test
          - features
      YAML
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.excluded_directories).to eq(["spec", "test", "features"])
    end

    it "defaults excluded_directories to spec, test, config" do
      create_config_file("")
      loader = described_class.new(working_dir: temp_dir)
      expect(loader.excluded_directories).to eq(%w[spec test config])
    end
  end

  describe "error handling" do
    it "handles invalid YAML gracefully" do
      create_config_file("invalid: yaml: content: [")
      expect do
        described_class.new(working_dir: temp_dir)
      end.to output(/Warning: Failed to parse/).to_stderr
    end

    it "handles non-hash YAML content gracefully" do
      create_config_file("- just\n- a\n- list")
      expect do
        described_class.new(working_dir: temp_dir)
      end.to output(/Warning.*not a valid configuration/).to_stderr
    end

    it "returns defaults when config file has parsing errors" do
      create_config_file("invalid: yaml: content: [")
      loader = nil
      expect do
        loader = described_class.new(working_dir: temp_dir)
      end.to output(/Warning/).to_stderr
      expect(loader.default_env).to eq("production")
      expect(loader.outputs).to eq([])
    end
  end

  describe "#to_h" do
    it "returns a hash representation of the configuration" do
      create_config_file(<<~YAML)
        grafana:
          url: https://grafana.example.com
          folder_id: 42
        default_env: staging
        app_name: my-app
      YAML
      loader = described_class.new(working_dir: temp_dir)
      hash = loader.to_h

      expect(hash[:grafana][:url]).to eq("https://grafana.example.com")
      expect(hash[:grafana][:folder_id]).to eq("42")
      expect(hash[:default_env]).to eq("staging")
      expect(hash[:app_name]).to eq("my-app")
      expect(hash[:loaded_from]).to include("diffdash.yml")
    end

    it "redacts the grafana token in the hash output" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DIFFDASH_GRAFANA_TOKEN").and_return("secret-token")
      loader = described_class.new(working_dir: temp_dir)
      hash = loader.to_h

      expect(hash[:grafana][:token]).to eq("[REDACTED]")
    end
  end
end
