# frozen_string_literal: true

module Diffdash
  module Signal
    # Base class for all observability signals
    class Base
      attr_reader :name, :type, :source_file, :metadata,
                  :defining_class, :inheritance_depth

      def initialize(
        name:,
        type:,
        source_file:,
        defining_class:,
        inheritance_depth:,
        metadata: {}
      )
        @name = name
        @type = type
        @source_file = source_file
        @defining_class = defining_class
        @inheritance_depth = inheritance_depth
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
