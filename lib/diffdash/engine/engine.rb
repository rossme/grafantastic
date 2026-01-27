# frozen_string_literal: true

module Diffdash
  module Engine
    # Vendor-agnostic core engine.
    # Produces structured signal intent from diff context.
    class Engine
      # Default to last 30 minutes - optimized for smoke testing freshly deployed code
      DEFAULT_TIME_RANGE = { from: "now-30m", to: "now" }.freeze

      attr_reader :dynamic_metrics, :limit_warnings

      def initialize(config:)
        @config = config
        @collector = Services::SignalCollector.new
        @dynamic_metrics = []
        @limit_warnings = []
      end

      def run(change_set: ChangeSet.from_git, time_range: DEFAULT_TIME_RANGE)
        signals = @collector.collect(change_set.filtered_files)
        @dynamic_metrics = @collector.dynamic_metrics

        # Truncate signals if limits exceeded and collect warnings
        validator = Validation::Limits.new(@config)
        signals = validator.truncate_and_validate(signals)
        @limit_warnings = validator.warnings

        bundle = SignalBundle.new(
          logs: build_queries(signals, :logs, time_range),
          metrics: build_queries(signals, :metrics, time_range),
          traces: [],
          metadata: {
            change_set: change_set.to_h,
            time_range: time_range,
            dynamic_metrics: @dynamic_metrics,
            limit_warnings: @limit_warnings
          }
        )

        bundle
      end

      private

      def build_queries(signals, type, time_range)
        signals.filter_map do |signal|
          query = Signal.from_domain(signal, time_range: time_range)
          query if query&.type == type
        end
      end
    end
  end
end
