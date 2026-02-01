# frozen_string_literal: true

module Diffdash
  module Linter
    # Formats lint issues for CLI output.
    #
    class Formatter
      def initialize(issues, verbose: false)
        @issues = issues
        @verbose = verbose
      end

      def format
        return no_issues_message if @issues.empty?

        if @verbose
          verbose_output
        else
          summary_output
        end
      end

      private

      def no_issues_message
        "No lint issues found. Your observability patterns look good!"
      end

      def summary_output
        lines = []

        grouped = @issues.group_by(&:rule)
        grouped.each do |rule, rule_issues|
          lines << format_rule_summary(rule, rule_issues)
        end

        lines << ""
        lines << example_block
        lines << ""
        lines << "Run 'diffdash lint --verbose' for details."

        lines.join("\n")
      end

      def verbose_output
        lines = []

        grouped = @issues.group_by(&:rule)
        grouped.each do |rule, rule_issues|
          lines << format_rule_header(rule, rule_issues.size)
          lines << ""

          rule_issues.each do |issue|
            lines << format_issue(issue)
            lines << ""
          end
        end

        lines << example_block
        lines << ""
        lines << format_summary

        lines.join("\n")
      end

      def format_rule_summary(rule, rule_issues)
        case rule
        when "interpolated-logs"
          "Found #{pluralize(rule_issues.size, 'log')} with string interpolation."
        else
          "Found #{pluralize(rule_issues.size, 'issue')} for rule: #{rule}"
        end
      end

      def format_rule_header(rule, count)
        case rule
        when "interpolated-logs"
          "Interpolated logs (#{count} found):"
        else
          "#{rule} (#{count} found):"
        end
      end

      def format_issue(issue)
        lines = []
        lines << "  #{relative_path(issue.file)}:#{issue.line}"

        if issue.context[:original]
          lines << "    #{issue.context[:original]}"
        end

        if issue.context[:static_match]
          lines << "    → Matches: \"#{issue.context[:static_match]}\""
        end

        if issue.suggestion
          lines << "    → Suggested: #{issue.suggestion}"
        end

        lines.join("\n")
      end

      def example_block
        <<~EXAMPLE.strip
          Consider structured logging for better observability:

            Before: logger.info("User \#{user.id} logged in")
            After:  logger.info("user_logged_in", user_id: user.id)
        EXAMPLE
      end

      def format_summary
        interpolated = @issues.count { |i| i.rule == "interpolated-logs" }
        "Summary: #{pluralize(interpolated, 'interpolated log')} found"
      end

      def relative_path(path)
        path.sub(%r{^#{Dir.pwd}/?}, "")
      end

      def pluralize(count, word)
        count == 1 ? "#{count} #{word}" : "#{count} #{word}s"
      end
    end
  end
end
