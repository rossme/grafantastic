# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Diffdash::Config do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  def create_config_file(content, dir: temp_dir)
    File.write(File.join(dir, 'diffdash.yml'), content)
  end

  # Use a working directory with no config file for ENV-based tests
  subject(:config) { described_class.new(working_dir: temp_dir) }

  describe 'guard rail limits' do
    it 'has MAX_LOGS of 10' do
      expect(config.max_logs).to eq(10)
    end

    it 'has MAX_METRICS of 10' do
      expect(config.max_metrics).to eq(10)
    end

    it 'has MAX_EVENTS of 5' do
      expect(config.max_events).to eq(5)
    end

    it 'has MAX_PANELS of 12' do
      expect(config.max_panels).to eq(12)
    end
  end

  describe '#grafana_url' do
    it 'prefers DIFFDASH_GRAFANA_URL when set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_GRAFANA_URL').and_return('https://diffdash.example.com')
      allow(ENV).to receive(:[]).with('GRAFANA_URL').and_return('https://grafana.example.com')
      expect(config.grafana_url).to eq('https://diffdash.example.com')
    end

    it 'falls back to GRAFANA_URL when DIFFDASH_GRAFANA_URL is not set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_GRAFANA_URL').and_return(nil)
      allow(ENV).to receive(:[]).with('GRAFANA_URL').and_return('https://grafana.example.com')
      expect(config.grafana_url).to eq('https://grafana.example.com')
    end

    it 'returns nil when not set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_GRAFANA_URL').and_return(nil)
      allow(ENV).to receive(:[]).with('GRAFANA_URL').and_return(nil)
      expect(config.grafana_url).to be_nil
    end

    it 'loads from config file when env vars not set' do
      create_config_file(<<~YAML)
        grafana:
          url: https://file.example.com
      YAML
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_GRAFANA_URL').and_return(nil)
      allow(ENV).to receive(:[]).with('GRAFANA_URL').and_return(nil)
      new_config = described_class.new(working_dir: temp_dir)
      expect(new_config.grafana_url).to eq('https://file.example.com')
    end
  end

  describe '#grafana_token' do
    it 'prefers DIFFDASH_GRAFANA_TOKEN when set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_GRAFANA_TOKEN').and_return('diffdash-token')
      allow(ENV).to receive(:[]).with('GRAFANA_TOKEN').and_return('secret-token')
      expect(config.grafana_token).to eq('diffdash-token')
    end

    it 'falls back to GRAFANA_TOKEN when DIFFDASH_GRAFANA_TOKEN is not set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_GRAFANA_TOKEN').and_return(nil)
      allow(ENV).to receive(:[]).with('GRAFANA_TOKEN').and_return('secret-token')
      expect(config.grafana_token).to eq('secret-token')
    end
  end

  describe '#grafana_folder_id' do
    it 'prefers DIFFDASH_GRAFANA_FOLDER_ID when set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_GRAFANA_FOLDER_ID').and_return('456')
      allow(ENV).to receive(:[]).with('GRAFANA_FOLDER_ID').and_return('123')
      expect(config.grafana_folder_id).to eq('456')
    end

    it 'falls back to GRAFANA_FOLDER_ID when DIFFDASH_GRAFANA_FOLDER_ID is not set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_GRAFANA_FOLDER_ID').and_return(nil)
      allow(ENV).to receive(:[]).with('GRAFANA_FOLDER_ID').and_return('123')
      expect(config.grafana_folder_id).to eq('123')
    end

    it 'loads from config file when env vars not set' do
      create_config_file(<<~YAML)
        grafana:
          folder_id: 99
      YAML
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_GRAFANA_FOLDER_ID').and_return(nil)
      allow(ENV).to receive(:[]).with('GRAFANA_FOLDER_ID').and_return(nil)
      new_config = described_class.new(working_dir: temp_dir)
      expect(new_config.grafana_folder_id).to eq('99')
    end
  end

  describe '#dry_run?' do
    it "returns true when DIFFDASH_DRY_RUN is 'true'" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_DRY_RUN').and_return('true')
      expect(config.dry_run?).to be true
    end

    it "returns false when DIFFDASH_DRY_RUN is not 'true'" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_DRY_RUN').and_return('false')
      expect(config.dry_run?).to be false
    end

    it 'returns false when DIFFDASH_DRY_RUN is not set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_DRY_RUN').and_return(nil)
      expect(config.dry_run?).to be false
    end
  end

  describe '#default_env' do
    it 'returns DIFFDASH_DEFAULT_ENV when set' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_DEFAULT_ENV').and_return('staging')
      expect(config.default_env).to eq('staging')
    end

    it "defaults to 'production' when not set" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_DEFAULT_ENV').and_return(nil)
      expect(config.default_env).to eq('production')
    end

    it 'loads from config file when env var not set' do
      create_config_file('default_env: development')
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_DEFAULT_ENV').and_return(nil)
      new_config = described_class.new(working_dir: temp_dir)
      expect(new_config.default_env).to eq('development')
    end
  end

  describe '#pr_comment?' do
    it 'returns true by default' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_PR_COMMENT').and_return(nil)
      expect(config.pr_comment?).to be true
    end

    it "returns false when DIFFDASH_PR_COMMENT is 'false'" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_PR_COMMENT').and_return('false')
      expect(config.pr_comment?).to be false
    end

    it 'returns true for any other value' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_PR_COMMENT').and_return('true')
      expect(config.pr_comment?).to be true
    end

    it 'loads from config file when env var not set' do
      create_config_file('pr_comment: false')
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DIFFDASH_PR_COMMENT').and_return(nil)
      new_config = described_class.new(working_dir: temp_dir)
      expect(new_config.pr_comment?).to be false
    end
  end

  describe '#loaded_from' do
    it 'returns nil when no config file is found' do
      expect(config.loaded_from).to be_nil
    end

    it 'returns the path to the loaded config file' do
      create_config_file('default_env: staging')
      new_config = described_class.new(working_dir: temp_dir)
      expect(new_config.loaded_from).to eq(File.join(temp_dir, 'diffdash.yml'))
    end
  end

  describe 'file filtering configuration' do
    it 'returns ignore_paths from config file' do
      create_config_file(<<~YAML)
        ignore_paths:
          - vendor/
          - lib/legacy/
      YAML
      new_config = described_class.new(working_dir: temp_dir)
      expect(new_config.ignore_paths).to eq(['vendor/', 'lib/legacy/'])
    end

    it 'returns include_paths from config file' do
      create_config_file(<<~YAML)
        include_paths:
          - app/
      YAML
      new_config = described_class.new(working_dir: temp_dir)
      expect(new_config.include_paths).to eq(['app/'])
    end

    it 'returns excluded_suffixes from config file' do
      create_config_file(<<~YAML)
        excluded_suffixes:
          - _spec.rb
          - _integration.rb
      YAML
      new_config = described_class.new(working_dir: temp_dir)
      expect(new_config.excluded_suffixes).to eq(['_spec.rb', '_integration.rb'])
    end

    it 'returns excluded_directories from config file' do
      create_config_file(<<~YAML)
        excluded_directories:
          - spec
          - features
      YAML
      new_config = described_class.new(working_dir: temp_dir)
      expect(new_config.excluded_directories).to eq(%w[spec features])
    end
  end

  describe '#to_h' do
    it 'returns a hash representation of the configuration' do
      create_config_file(<<~YAML)
        grafana:
          url: https://grafana.example.com
        default_env: staging
      YAML
      new_config = described_class.new(working_dir: temp_dir)
      hash = new_config.to_h

      expect(hash[:grafana][:url]).to eq('https://grafana.example.com')
      expect(hash[:default_env]).to eq('staging')
      expect(hash[:max_logs]).to eq(10)
      expect(hash[:max_panels]).to eq(12)
    end
  end
end
