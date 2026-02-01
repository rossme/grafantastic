# frozen_string_literal: true

module Diffdash
  module Linter
    # Orchestrates lint rules across files.
    # Collects issues and formats output.
    #
    class Runner
      attr_reader :issues

      DEFAULT_RULES = [
        InterpolatedLogs
      ].freeze

      def initialize(rules: DEFAULT_RULES, config: nil)
        @rules = rules.map(&:new)
        @config = config
        @issues = []
      end

      # Run all rules against the given files
      # @param files [Array<String>] File paths to analyze
      # @return [Array<Base::Issue>] All issues found
      def run(files)
        @issues = []

        files.each do |file|
          analyze_file(file)
        end

        @issues
      end

      # Run against a ChangeSet (for integration with existing flow)
      # @param change_set [Engine::ChangeSet]
      # @return [Array<Base::Issue>]
      def run_on_change_set(change_set)
        run(change_set.filtered_files)
      end

      def issues_by_rule
        @issues.group_by(&:rule)
      end

      def issue_count
        @issues.size
      end

      def rules_with_issues
        issues_by_rule.keys
      end

      private

      def analyze_file(file)
        return unless File.exist?(file)

        source = File.read(file)
        ast = AST::Parser.parse(source, file)
        return unless ast

        visitor = AST::Visitor.new(file_path: file, inheritance_depth: 0)
        visitor.process(ast)

        # Check log calls against all rules
        visitor.log_calls.each do |log_call|
          @rules.each do |rule|
            issue = rule.check(log_call, file)
            @issues << issue if issue
          end
        end
      rescue ::Parser::SyntaxError, StandardError => e
        # Skip files that can't be parsed
        nil
      end
    end
  end
end
