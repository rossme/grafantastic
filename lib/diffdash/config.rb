# frozen_string_literal: true

module Diffdash
  class Config
    # Hard guard rail limits - not configurable for PoC
    MAX_LOGS    = 10
    MAX_METRICS = 10
    MAX_EVENTS  = 5
    MAX_PANELS  = 12

    attr_reader :max_logs, :max_metrics, :max_events, :max_panels

    def initialize
      @max_logs = MAX_LOGS
      @max_metrics = MAX_METRICS
      @max_events = MAX_EVENTS
      @max_panels = MAX_PANELS
    end

    def grafana_url
      ENV["DIFFDASH_GRAFANA_URL"] || ENV["GRAFANA_URL"]
    end

    def grafana_token
      ENV["DIFFDASH_GRAFANA_TOKEN"] || ENV["GRAFANA_TOKEN"]
    end

    def grafana_folder_id
      ENV["DIFFDASH_GRAFANA_FOLDER_ID"] || ENV["GRAFANA_FOLDER_ID"]
    end

    def outputs
      raw = ENV["DIFFDASH_OUTPUTS"].to_s
      return [:grafana] if raw.strip.empty?

      raw.split(",")
         .map(&:strip)
         .reject(&:empty?)
         .map(&:downcase)
         .map(&:to_sym)
    end

    def dry_run?
      ENV["DIFFDASH_DRY_RUN"] == "true"
    end

    def default_env
      ENV["DIFFDASH_DEFAULT_ENV"] || "production"
    end

    def pr_comment?
      ENV["DIFFDASH_PR_COMMENT"] != "false"
    end
  end
end
