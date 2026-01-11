# frozen_string_literal: true

require_relative "base"

module Grafantastic
  module Signal
    # Represents a detected log statement (logger.info, Rails.logger.error, etc.)
    class Log < Base
      def initialize(
        name:,
        source_file:,
        defining_class:,
        inheritance_depth:,
        labels: {},
        confidence: :high,
        metadata: {}
      )
        super(
          name: name,
          type: :log,
          source_file: source_file,
          defining_class: defining_class,
          inheritance_depth: inheritance_depth,
          labels: labels,
          confidence: confidence,
          metadata: metadata
        )
      end

      def log?
        true
      end

      def level
        metadata[:level]
      end

      def line
        metadata[:line]
      end
    end
  end
end
