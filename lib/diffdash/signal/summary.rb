# frozen_string_literal: true

require_relative 'base'

module Diffdash
  module Signal
    # Represents a detected summary metric (Prometheus.summary, etc.)
    class Summary < Base
      def initialize(
        name:,
        source_file:,
        defining_class:,
        inheritance_depth:,
        metadata: {}
      )
        metadata_with_type = metadata.merge(metric_type: :summary)

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
