# frozen_string_literal: true

require_relative "base"

module Grafantastic
  module Signal
    # Represents a detected gauge metric (Prometheus.gauge, StatsD.gauge, etc.)
    class Gauge < Base
      def initialize(
        name:,
        source_file:,
        defining_class:,
        inheritance_depth:,
        labels: {},
        confidence: :high,
        metadata: {}
      )
        # Ensure metric_type is set for backward compatibility
        metadata_with_type = metadata.merge(metric_type: :gauge)

        super(
          name: name,
          type: :metric,
          source_file: source_file,
          defining_class: defining_class,
          inheritance_depth: inheritance_depth,
          labels: labels,
          confidence: confidence,
          metadata: metadata_with_type
        )
      end

      def metric?
        true
      end

      def line
        metadata[:line]
      end
    end
  end
end
