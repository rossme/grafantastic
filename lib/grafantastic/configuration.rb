# frozen_string_literal: true

require "yaml"
require "fileutils"

module Grafantastic
  class Configuration
    CONFIG_FILE_NAME = ".grafantastic.yml"
    GLOBAL_CONFIG_PATH = File.join(Dir.home, CONFIG_FILE_NAME)

    VALID_KEYS = %w[
      grafana_url
      grafana_token
      grafana_folder_id
      grafana_folder_name
    ].freeze

    attr_accessor :grafana_url, :grafana_token, :grafana_folder_id, :grafana_folder_name

    def initialize
      load_config
    end

    # Load config with precedence: ENV > local .grafantastic.yml > ~/.grafantastic.yml
    def load_config
      global_config = load_file(GLOBAL_CONFIG_PATH)
      local_config = load_file(local_config_path)

      merged = global_config.merge(local_config)

      @grafana_url = ENV["GRAFANA_URL"] || merged["grafana_url"]
      @grafana_token = ENV["GRAFANA_TOKEN"] || merged["grafana_token"]
      @grafana_folder_id = ENV["GRAFANA_FOLDER_ID"] || merged["grafana_folder_id"]
      @grafana_folder_name = merged["grafana_folder_name"]
    end

    def save(key, value, global: false)
      raise ArgumentError, "Invalid config key: #{key}" unless VALID_KEYS.include?(key)

      path = global ? GLOBAL_CONFIG_PATH : local_config_path
      config = load_file(path)
      config[key] = value
      write_file(path, config)
    end

    def delete(key, global: false)
      raise ArgumentError, "Invalid config key: #{key}" unless VALID_KEYS.include?(key)

      path = global ? GLOBAL_CONFIG_PATH : local_config_path
      config = load_file(path)
      config.delete(key)
      write_file(path, config)
    end

    def show
      {
        "grafana_url" => grafana_url,
        "grafana_token" => grafana_token ? "[REDACTED]" : nil,
        "grafana_folder_id" => grafana_folder_id,
        "grafana_folder_name" => grafana_folder_name
      }.compact
    end

    def configured?
      !grafana_url.nil? && !grafana_token.nil?
    end

    private

    def local_config_path
      File.join(Dir.pwd, CONFIG_FILE_NAME)
    end

    def load_file(path)
      return {} unless File.exist?(path)

      YAML.safe_load(File.read(path)) || {}
    rescue Psych::SyntaxError => e
      warn "[grafantastic] Warning: Could not parse #{path}: #{e.message}"
      {}
    end

    def write_file(path, config)
      return if config.empty?

      File.write(path, YAML.dump(config))
      File.chmod(0o600, path) if path == GLOBAL_CONFIG_PATH # Protect token
    end
  end
end
