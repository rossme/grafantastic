# frozen_string_literal: true

module Grafantastic
  module Signals
    class Signal
      attr_reader :type, :name, :source_file, :defining_class,
                  :inheritance_depth, :metadata

      def initialize(type:, name:, source_file:, defining_class:, inheritance_depth:, metadata: {})
        @type = type
        @name = name
        @source_file = source_file
        @defining_class = defining_class
        @inheritance_depth = inheritance_depth
        @metadata = metadata
      end

      def log?
        type == :log
      end

      def metric?
        type == :metric
      end

      def event?
        type == :event
      end

      def to_h
        {
          type: type,
          name: name,
          source_file: source_file,
          defining_class: defining_class,
          inheritance_depth: inheritance_depth,
          metadata: metadata
        }
      end
    end
  end
end
