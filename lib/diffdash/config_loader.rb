# frozen_string_literal: true

require 'yaml'

module Diffdash
  # Loads configuration from diffdash.yml files with environment variable overrides.
  #
  # Configuration is loaded from the following sources in order of precedence:
  # 1. Environment variables (highest priority)
  # 2. Explicitly specified config file via --config flag
  # 3. diffdash.yml in the current working directory
  # 4. diffdash.yml in the git repository root
  # 5. Default values (lowest priority)
  #
  # Example diffdash.yml:
  #
  #   grafana:
  #     url: https://grafana.mycompany.com
  #     folder_id: 42
  #
  #   ignore_paths:
  #     - vendor/
  #     - tmp/
  #     - lib/legacy/
  #
  #   outputs:
  #     - grafana
  #     - json
  #
  #   default_env: production
  #   pr_comment: true
  #   app_name: my-service
  #
  class ConfigLoader
    CONFIG_FILE_NAMES = %w[diffdash.yml diffdash.yaml .diffdash.yml .diffdash.yaml].freeze

    attr_reader :config_path, :loaded_from

    def initialize(config_path: nil, working_dir: nil)
      @explicit_config_path = config_path
      @working_dir = working_dir || Dir.pwd
      @file_config = {}
      @loaded_from = nil
      load_config_file
    end

    # Grafana configuration
    def grafana_url
      env_value('DIFFDASH_GRAFANA_URL') ||
        env_value('GRAFANA_URL') ||
        file_value('grafana', 'url')
    end

    def grafana_token
      # Token should NOT be loaded from file for security - only env vars
      env_value('DIFFDASH_GRAFANA_TOKEN') || env_value('GRAFANA_TOKEN')
    end

    def grafana_folder_id
      env_value('DIFFDASH_GRAFANA_FOLDER_ID') ||
        env_value('GRAFANA_FOLDER_ID') ||
        file_value('grafana', 'folder_id')&.to_s
    end

    # Output configuration
    def outputs
      raw_env = env_value('DIFFDASH_OUTPUTS')
      return parse_outputs_string(raw_env) if raw_env && !raw_env.strip.empty?

      file_outputs = file_value('outputs')
      return file_outputs.map { |o| o.to_s.downcase.to_sym } if file_outputs.is_a?(Array) && file_outputs.any?

      [] # no default - require explicit output
    end

    # General settings
    def dry_run?
      env_value('DIFFDASH_DRY_RUN') == 'true'
    end

    def default_env
      env_value('DIFFDASH_DEFAULT_ENV') ||
        file_value('default_env') ||
        'production'
    end

    def pr_comment?
      env_val = env_value('DIFFDASH_PR_COMMENT')
      return env_val != 'false' unless env_val.nil?

      file_val = file_value('pr_comment')
      return file_val != false unless file_val.nil?

      true # default
    end

    def app_name
      env_value('DIFFDASH_APP_NAME') || file_value('app_name')
    end

    def pr_deploy_annotation_expr
      env_value('DIFFDASH_PR_DEPLOY_ANNOTATION_EXPR') ||
        file_value('pr_deploy_annotation_expr')
    end

    # File filtering configuration
    def ignore_paths
      file_value('ignore_paths') || []
    end

    def include_paths
      file_value('include_paths') || []
    end

    def excluded_suffixes
      file_value('excluded_suffixes') || %w[_spec.rb _test.rb]
    end

    def excluded_directories
      file_value('excluded_directories') || %w[spec test config]
    end

    # Signal filtering configuration
    # Options: :include (default), :warn, :exclude
    def interpolated_logs
      env_val = env_value('DIFFDASH_INTERPOLATED_LOGS')
      return env_val.to_sym if env_val && %w[include warn exclude].include?(env_val)

      file_val = file_value('signals', 'interpolated_logs')
      return file_val.to_sym if file_val && %w[include warn exclude].include?(file_val.to_s)

      :include # default - include all logs
    end

    # Returns the full configuration as a hash (useful for debugging)
    def to_h
      {
        loaded_from: @loaded_from,
        grafana: {
          url: grafana_url,
          token: grafana_token ? '[REDACTED]' : nil,
          folder_id: grafana_folder_id
        },
        outputs: outputs,
        default_env: default_env,
        dry_run: dry_run?,
        pr_comment: pr_comment?,
        app_name: app_name,
        ignore_paths: ignore_paths,
        include_paths: include_paths,
        excluded_suffixes: excluded_suffixes,
        excluded_directories: excluded_directories,
        interpolated_logs: interpolated_logs
      }
    end

    private

    def load_config_file
      @config_path = find_config_file
      return unless @config_path

      begin
        @file_config = YAML.load_file(@config_path, permitted_classes: [Symbol]) || {}
        @loaded_from = @config_path

        unless @file_config.is_a?(Hash)
          warn "[diffdash] Warning: #{@config_path} is not a valid configuration (expected hash)"
          @file_config = {}
        end
      rescue Psych::SyntaxError => e
        warn "[diffdash] Warning: Failed to parse #{@config_path}: #{e.message}"
        @file_config = {}
      rescue Errno::ENOENT
        @file_config = {}
      end
    end

    def find_config_file
      # 1. Explicit config path takes highest priority
      if @explicit_config_path
        return @explicit_config_path if File.exist?(@explicit_config_path)

        warn "[diffdash] Warning: Config file not found: #{@explicit_config_path}"
        return nil
      end

      # 2. Check working directory
      CONFIG_FILE_NAMES.each do |name|
        path = File.join(@working_dir, name)
        return path if File.exist?(path)
      end

      # 3. Check git root (if different from working directory)
      git_root = find_git_root
      if git_root && git_root != @working_dir
        CONFIG_FILE_NAMES.each do |name|
          path = File.join(git_root, name)
          return path if File.exist?(path)
        end
      end

      nil
    end

    def find_git_root
      dir = @working_dir
      loop do
        return dir if File.directory?(File.join(dir, '.git'))

        parent = File.dirname(dir)
        return nil if parent == dir # reached filesystem root

        dir = parent
      end
    end

    def env_value(key)
      val = ENV[key]
      val.nil? || val.empty? ? nil : val
    end

    def file_value(*keys)
      keys.reduce(@file_config) do |hash, key|
        return nil unless hash.is_a?(Hash)

        # Use key? to check existence since || doesn't work with false values
        if hash.key?(key.to_s)
          hash[key.to_s]
        elsif hash.key?(key.to_sym)
          hash[key.to_sym]
        end
      end
    end

    def parse_outputs_string(raw)
      raw.split(',')
         .map(&:strip)
         .reject(&:empty?)
         .map(&:downcase)
         .map(&:to_sym)
    end
  end
end
