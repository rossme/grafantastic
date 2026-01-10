# frozen_string_literal: true

module Grafantastic
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
      ENV["GRAFANA_URL"]
    end

    def grafana_token
      ENV["GRAFANA_TOKEN"]
    end

    def grafana_folder_id
      ENV["GRAFANA_FOLDER_ID"]
    end

    def dry_run?
      ENV["GRAFANTASTIC_DRY_RUN"] == "true"
    end
  end
end
