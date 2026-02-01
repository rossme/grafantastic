# frozen_string_literal: true

require_relative 'base'

module Diffdash
  module Signal
    # Represents a detected histogram metric (Prometheus.histogram, StatsD.timing, etc.)
    class Histogram < Base
      def initialize(
        name:,
        source_file:,
        defining_class:,
        inheritance_depth:,
        metadata: {}
      )
        metadata_with_type = metadata.merge(metric_type: :histogram)

        super(
          name: name,
          type: :metric,
          source_file: source_file,
          defining_class: defining_class,
          inheritance_depth: inheritance_depth,
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
