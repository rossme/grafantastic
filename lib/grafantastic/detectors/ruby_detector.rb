# frozen_string_literal: true

module Grafantastic
  module Detectors
    # Detects observability signals from Ruby source code
    # Input: Ruby source text + metadata
    # Output: Array of Signal objects
    # No Grafana-specific knowledge
    class RubyDetector
      def initialize
        @parser = AST::Parser
      end

      # Detect signals in Ruby source code
      # @param source [String] Ruby source code
      # @param file_path [String] Path to the source file
      # @param inheritance_depth [Integer] How many levels deep in inheritance
      # @return [Array<Signal::Base>] Array of detected signals
      def detect(source:, file_path:, inheritance_depth: 0)
        result = detect_with_metadata(source: source, file_path: file_path, inheritance_depth: inheritance_depth)
        result[:signals]
      end

      # Detect signals and additional metadata (e.g., dynamic metrics that can't be analyzed)
      # @param source [String] Ruby source code
      # @param file_path [String] Path to the source file
      # @param inheritance_depth [Integer] How many levels deep in inheritance
      # @return [Hash] Hash with :signals and :dynamic_metrics
      def detect_with_metadata(source:, file_path:, inheritance_depth: 0)
        ast = @parser.parse(source, file_path)
        return { signals: [], dynamic_metrics: [] } unless ast

        visitor = AST::Visitor.new(file_path: file_path, inheritance_depth: inheritance_depth)
        visitor.process(ast)

        signals = []
        signals.concat(extract_logs(visitor))
        signals.concat(extract_metrics(visitor))

        {
          signals: signals,
          dynamic_metrics: visitor.dynamic_metric_calls || []
        }
      end

      # Detect class definitions and included modules for ancestor resolution
      # @param source [String] Ruby source code
      # @param file_path [String] Path to the source file
      # @return [Hash] Hash with :class_definitions, :included_modules, etc.
      def detect_structure(source:, file_path:)
        ast = @parser.parse(source, file_path)
        return default_structure unless ast

        visitor = AST::Visitor.new(file_path: file_path, inheritance_depth: 0)
        visitor.process(ast)

        {
          class_definitions: visitor.class_definitions,
          module_definitions: visitor.module_definitions,
          included_modules: visitor.included_modules,
          prepended_modules: visitor.prepended_modules,
          extended_modules: visitor.extended_modules
        }
      end

      private

      def extract_logs(visitor)
        Signals::LogExtractor.extract(visitor)
      end

      def extract_metrics(visitor)
        Signals::MetricExtractor.extract(visitor)
      end

      def default_structure
        {
          class_definitions: [],
          module_definitions: [],
          included_modules: [],
          prepended_modules: [],
          extended_modules: []
        }
      end
    end
  end
end
