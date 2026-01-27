# frozen_string_literal: true

module Diffdash
  module Engine
    # Container for signals returned by the engine.
    # Keeps engine output serialisable and side-effect free.
    class SignalBundle
      attr_reader :logs, :metrics, :traces, :metadata

      def initialize(logs: [], metrics: [], traces: [], metadata: {})
        @logs = logs
        @metrics = metrics
        @traces = traces
        @metadata = metadata
      end

      def empty?
        logs.empty? && metrics.empty? && traces.empty?
      end

      def to_h
        {
          logs: logs.map(&:to_h),
          metrics: metrics.map(&:to_h),
          traces: traces.map(&:to_h),
          metadata: metadata
        }
      end
    end
  end
end
