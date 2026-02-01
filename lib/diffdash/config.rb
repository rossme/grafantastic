# frozen_string_literal: true

require_relative 'config_loader'

module Diffdash
  class Config
    # Hard guard rail limits - not configurable for PoC
    MAX_LOGS    = 10
    MAX_METRICS = 10
    MAX_EVENTS  = 5
    MAX_PANELS  = 12

    attr_reader :max_logs, :max_metrics, :max_events, :max_panels, :loader

    # Initialize Config with optional YAML file support.
    #
    # @param config_path [String, nil] explicit path to diffdash.yml
    # @param working_dir [String, nil] working directory to search for config files
    def initialize(config_path: nil, working_dir: nil)
      @max_logs = MAX_LOGS
      @max_metrics = MAX_METRICS
      @max_events = MAX_EVENTS
      @max_panels = MAX_PANELS
      @loader = ConfigLoader.new(config_path: config_path, working_dir: working_dir)
    end

    # Returns the path to the loaded config file, or nil if none was loaded.
    def loaded_from
      @loader.loaded_from
    end

    def grafana_url
      @loader.grafana_url
    end

    def grafana_token
      @loader.grafana_token
    end

    def grafana_folder_id
      @loader.grafana_folder_id
    end

    def outputs
      @loader.outputs
    end

    def dry_run?
      @loader.dry_run?
    end

    def default_env
      @loader.default_env
    end

    def pr_comment?
      @loader.pr_comment?
    end

    def app_name
      @loader.app_name
    end

    def pr_deploy_annotation_expr
      @loader.pr_deploy_annotation_expr
    end

    # File filtering configuration (new YAML-configurable options)
    def ignore_paths
      @loader.ignore_paths
    end

    def include_paths
      @loader.include_paths
    end

    def excluded_suffixes
      @loader.excluded_suffixes
    end

    def excluded_directories
      @loader.excluded_directories
    end

    # Signal filtering - :include, :warn, or :exclude
    def interpolated_logs
      @loader.interpolated_logs
    end

    # Returns the full configuration as a hash (useful for debugging)
    def to_h
      @loader.to_h.merge(
        max_logs: max_logs,
        max_metrics: max_metrics,
        max_events: max_events,
        max_panels: max_panels
      )
    end
  end
end
