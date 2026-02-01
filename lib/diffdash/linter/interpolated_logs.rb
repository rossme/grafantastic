# frozen_string_literal: true

module Diffdash
  module Linter
    # Detects log calls with string interpolation and suggests structured logging.
    #
    # Why this matters:
    # - Interpolated logs like `logger.info("User #{id} logged in")` are hard to query
    # - Diffdash can only match on static parts: "User " and " logged in"
    # - Structured logs like `logger.info("user_logged_in", user_id: id)` are exact matches
    #
    class InterpolatedLogs < Base
      def rule_name
        "interpolated-logs"
      end

      def description
        "Logs with string interpolation are harder to query in observability tools"
      end

      # @param log_call [Hash] Contains :node, :event_name, :method, :receiver, :line, etc.
      # @param source_file [String] Path to source file
      # @return [Issue, nil]
      def check(log_call, source_file)
        node = log_call[:node]
        return nil unless node

        # Get the first argument (the log message)
        args = node.children[2..]&.compact || []
        return nil if args.empty?

        first_arg = args.first
        return nil unless first_arg&.type == :dstr

        # It's an interpolated string - create an issue
        static_parts = extract_static_parts(first_arg)
        interpolations = extract_interpolations(first_arg)

        Issue.new(
          rule: rule_name,
          file: source_file,
          line: log_call[:line] || node.loc&.line,
          message: "Log uses string interpolation",
          suggestion: build_suggestion(static_parts, interpolations, log_call[:method]),
          context: {
            original: reconstruct_string(first_arg),
            static_match: static_parts.join,
            interpolation_count: interpolations.size
          }
        )
      end

      private

      def extract_static_parts(dstr_node)
        dstr_node.children
          .select { |c| c.type == :str }
          .map { |c| c.children.first }
      end

      def extract_interpolations(dstr_node)
        dstr_node.children
          .reject { |c| c.type == :str }
          .map { |c| extract_variable_name(c) }
          .compact
      end

      def extract_variable_name(node)
        case node.type
        when :begin
          # #{expression} - get the inner expression
          extract_variable_name(node.children.first)
        when :send
          # method call like user.id
          receiver = node.children[0]
          method = node.children[1]
          if receiver
            "#{extract_variable_name(receiver)}_#{method}"
          else
            method.to_s
          end
        when :lvar, :ivar
          # local or instance variable
          node.children.first.to_s.delete_prefix("@")
        when :str
          nil
        else
          "value"
        end
      end

      def reconstruct_string(dstr_node)
        dstr_node.children.map do |child|
          case child.type
          when :str
            child.children.first
          when :begin
            "\#{#{extract_variable_name(child)}}"
          else
            "\#{...}"
          end
        end.join
      end

      def build_suggestion(static_parts, interpolations, log_method)
        # Generate an event name from static parts
        event_name = static_parts
          .join(" ")
          .downcase
          .gsub(/[^a-z0-9]+/, "_")
          .gsub(/^_|_$/, "")

        event_name = "log_event" if event_name.empty?

        # Build keyword arguments from interpolations
        kwargs = interpolations.map { |name| "#{name}: #{name}" }.join(", ")

        if kwargs.empty?
          "logger.#{log_method}(\"#{event_name}\")"
        else
          "logger.#{log_method}(\"#{event_name}\", #{kwargs})"
        end
      end
    end
  end
end
