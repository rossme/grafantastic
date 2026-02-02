# frozen_string_literal: true

module Diffdash
  module Services
    # Orchestrates signal detection across files and their ancestors
    # Responsibilities:
    #   - Read source files
    #   - Call detector for each file
    #   - Resolve and traverse ancestor hierarchy
    #   - Collect dynamic metrics (unresolvable signals)
    #   - Deduplicate results
    #   - Resolve metric constants (e.g., Metrics::RequestTotal → "request_total")
    #
    # This is orchestration logic extracted from CLI
    class SignalCollector
      # Common locations for metric constant definitions
      METRIC_DEFINITION_PATTERNS = %w[
        app/services/metrics.rb
        lib/metrics.rb
        app/lib/metrics.rb
        config/initializers/metrics.rb
      ].freeze

      attr_reader :dynamic_metrics

      def initialize
        @ancestor_resolver = AST::AncestorResolver.new
        @dynamic_metrics = []
        @constant_resolver = nil
      end

      # Collect all signals from given files, including inherited signals
      # @param file_paths [Array<String>] Paths to Ruby files to analyze
      # @return [Array<Signal::Base>] Deduplicated array of detected signals
      def collect(file_paths)
        signals = []

        # Build constant resolver from metric definition files
        build_constant_resolver(file_paths)
        detector = Detectors::RubyDetector.new(constant_resolver: @constant_resolver)

        file_paths.each do |file_path|
          next unless File.exist?(file_path)

          source = File.read(file_path)

          # Detect signals in the primary file
          result = detector.detect_with_metadata(
            source: source,
            file_path: file_path,
            inheritance_depth: 0
          )

          signals.concat(result[:signals])
          collect_dynamic_metrics(result[:dynamic_metrics], file_path)

          # Resolve and process ancestors (parent classes, included modules)
          signals.concat(collect_from_ancestors(source, file_path, detector))
        end

        # Deduplicate by unique signal characteristics
        signals.uniq { |s| [s.type, s.name, s.source_file, s.defining_class] }
      end

      private

      def build_constant_resolver(file_paths)
        @constant_resolver = AST::ConstantResolver.new

        # Find metric definition files relative to the project
        git_root = find_git_root(file_paths.first)
        return unless git_root

        METRIC_DEFINITION_PATTERNS.each do |pattern|
          path = File.join(git_root, pattern)
          next unless File.exist?(path)

          source = File.read(path)
          @constant_resolver.scan(source, path)
        end

        # Also scan any changed files that might define constants
        file_paths.each do |file_path|
          next unless File.exist?(file_path)

          source = File.read(file_path)
          @constant_resolver.scan(source, file_path)
        end
      end

      def find_git_root(file_path)
        return nil unless file_path

        dir = File.dirname(File.expand_path(file_path))
        loop do
          return dir if File.directory?(File.join(dir, '.git'))

          parent = File.dirname(dir)
          return nil if parent == dir

          dir = parent
        end
      end

      def collect_from_ancestors(source, file_path, detector)
        signals = []

        # Determine class/module structure
        structure = detector.detect_structure(source: source, file_path: file_path)

        # Recursively find all ancestors
        ancestors = @ancestor_resolver.collect_ancestors_from_structure(structure, file_path)

        ancestors.each do |ancestor|
          next unless File.exist?(ancestor[:file])

          ancestor_source = File.read(ancestor[:file])

          # Detect signals in ancestor
          result = detector.detect_with_metadata(
            source: ancestor_source,
            file_path: ancestor[:file],
            inheritance_depth: ancestor[:depth]
          )

          signals.concat(result[:signals])
          collect_dynamic_metrics(result[:dynamic_metrics], ancestor[:file])
        end

        signals
      end

      def collect_dynamic_metrics(metric_calls, file_path)
        metric_calls.each do |call|
          @dynamic_metrics << {
            file: file_path,
            line: call[:line],
            type: call[:metric_type],
            class: call[:defining_class],
            receiver: call[:receiver]
          }
        end
      end
    end
  end
end
