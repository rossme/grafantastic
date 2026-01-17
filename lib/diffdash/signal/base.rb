# frozen_string_literal: true

module Diffdash
  module Signal
    # Base class for all observability signals
    class Base
      attr_reader :name, :type, :source_file, :labels, :confidence, :metadata,
                  :defining_class, :inheritance_depth

      def initialize(
        name:,
        type:,
        source_file:,
        defining_class:,
        inheritance_depth:,
        labels: {},
        confidence: :high,
        metadata: {}
      )
        @name = name
        @type = type
        @source_file = source_file
        @defining_class = defining_class
        @inheritance_depth = inheritance_depth
        @labels = labels
        @confidence = confidence
        @metadata = metadata
      end

      def log?
        false
      end

      def metric?
        false
      end

      def event?
        false
      end

      # Maintain compatibility with existing code expecting hash representation
      def to_h
        {
          type: type,
          name: name,
          source_file: source_file,
          defining_class: defining_class,
          inheritance_depth: inheritance_depth,
          labels: labels,
          confidence: confidence,
          metadata: metadata
        }
      end
    end
  end
end
