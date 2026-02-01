# frozen_string_literal: true

module Diffdash
  module Engine
    # Vendor-agnostic core engine.
    # Produces structured signal intent from diff context.
    class Engine
      # Default to last 30 minutes - optimized for smoke testing freshly deployed code
      DEFAULT_TIME_RANGE = { from: 'now-30m', to: 'now' }.freeze

      attr_reader :dynamic_metrics, :limit_warnings, :excluded_interpolated_count

      def initialize(config:)
        @config = config
        @collector = Services::SignalCollector.new
        @dynamic_metrics = []
        @limit_warnings = []
        @excluded_interpolated_count = 0
      end

      def run(change_set: ChangeSet.from_git, time_range: DEFAULT_TIME_RANGE)
        signals = @collector.collect(change_set.filtered_files)
        @dynamic_metrics = @collector.dynamic_metrics

        # Filter out interpolated logs if configured
        signals = filter_interpolated_logs(signals)

        # Truncate signals if limits exceeded and collect warnings
        validator = Validation::Limits.new(@config)
        signals = validator.truncate_and_validate(signals)
        @limit_warnings = validator.warnings

        SignalBundle.new(
          logs: build_queries(signals, :logs, time_range),
          metrics: build_queries(signals, :metrics, time_range),
          traces: [],
          metadata: {
            change_set: change_set.to_h,
            time_range: time_range,
            dynamic_metrics: @dynamic_metrics,
            limit_warnings: @limit_warnings,
            excluded_interpolated_count: @excluded_interpolated_count
          }
        )
      end

      private

      def filter_interpolated_logs(signals)
        return signals unless @config.interpolated_logs == :exclude

        filtered = signals.reject do |signal|
          signal.is_a?(Diffdash::Signal::Log) && signal.metadata[:interpolated]
        end

        @excluded_interpolated_count = signals.size - filtered.size
        filtered
      end

      def build_queries(signals, type, time_range)
        signals.filter_map do |signal|
          query = Signal.from_domain(signal, time_range: time_range)
          query if query&.type == type
        end
      end
    end
  end
end
