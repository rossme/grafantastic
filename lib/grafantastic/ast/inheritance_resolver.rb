# frozen_string_literal: true

module Grafantastic
  module AST
    class InheritanceResolver
      def initialize
        @resolved_cache = {}
      end

      def resolve_parent(parent_class_name, current_file)
        return unless parent_class_name
        return @resolved_cache[parent_class_name] if @resolved_cache.key?(parent_class_name)

        # Best-effort resolution strategies
        resolved = resolve_by_convention(parent_class_name, current_file) ||
                   resolve_by_grep(parent_class_name)

        @resolved_cache[parent_class_name] = resolved
        resolved
      end

      private

      def resolve_by_convention(class_name, current_file)
        # Convert class name to potential file paths
        # PaymentProcessor -> payment_processor.rb
        base_name = class_name
          .gsub(/::/, "/")
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase

        current_dir = File.dirname(current_file)

        # Search patterns
        patterns = [
          File.join(current_dir, "#{base_name}.rb"),
          File.join(current_dir, "..", "#{base_name}.rb"),
          File.join("app", "**", "#{base_name}.rb"),
          File.join("lib", "**", "#{base_name}.rb")
        ]

        patterns.each do |pattern|
          matches = Dir.glob(pattern)
          # Filter out test/spec files
          matches.reject! { |f| f.match?(%r{/(spec|test)/}) || f.end_with?("_spec.rb", "_test.rb") }
          return matches.first if matches.any?
        end

        nil
      end

      def resolve_by_grep(class_name)
        # Use grep to find class definition
        pattern = "^\\s*class\\s+#{Regexp.escape(class_name)}\\b"
        result = `grep -rl "#{pattern}" --include="*.rb" app lib 2>/dev/null`.strip

        return nil if result.empty?

        files = result.split("\n")
        files.reject! { |f| f.match?(%r{/(spec|test)/}) || f.end_with?("_spec.rb", "_test.rb") }
        files.first
      end
    end
  end
end
