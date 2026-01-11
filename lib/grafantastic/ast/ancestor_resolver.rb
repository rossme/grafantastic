# frozen_string_literal: true

require "set"

module Grafantastic
  module AST
    class AncestorResolver
      MAX_DEPTH = 5 # Prevent infinite loops

      def initialize
        @resolved_cache = {}
      end

      # Resolve a parent class or included module to its file path
      def resolve(name, current_file)
        return unless name
        return @resolved_cache[name] if @resolved_cache.key?(name)

        resolved = resolve_by_convention(name, current_file) ||
                   resolve_by_grep(name)

        @resolved_cache[name] = resolved
        resolved
      end

      # Alias for backwards compatibility
      alias resolve_parent resolve

      # Recursively collect all ancestors (parents + included modules)
      # Returns array of { name:, file:, depth:, type: :class/:module }
      def collect_ancestors(visitor, current_file, current_depth: 0, visited: nil)
        visited ||= Set.new
        return [] if current_depth >= MAX_DEPTH

        ancestors = []

        # Collect parent classes
        visitor.class_definitions.each do |class_def|
          next unless class_def[:parent]
          next if visited.include?(class_def[:parent])

          parent_file = resolve(class_def[:parent], current_file)
          next unless parent_file && File.exist?(parent_file)

          visited.add(class_def[:parent])
          ancestors << {
            name: class_def[:parent],
            file: parent_file,
            depth: current_depth + 1,
            type: :class
          }

          # Recursively get grandparents
          parent_source = File.read(parent_file)
          parent_ast = Parser.parse(parent_source, parent_file)
          if parent_ast
            parent_visitor = Visitor.new(file_path: parent_file, inheritance_depth: current_depth + 1)
            parent_visitor.process(parent_ast)
            ancestors.concat(
              collect_ancestors(parent_visitor, parent_file, current_depth: current_depth + 1, visited: visited)
            )
          end
        end

        # Collect included modules
        visitor.included_modules.each do |mod|
          next if visited.include?(mod[:module_name])

          module_file = resolve(mod[:module_name], current_file)
          next unless module_file && File.exist?(module_file)

          visited.add(mod[:module_name])
          ancestors << {
            name: mod[:module_name],
            file: module_file,
            depth: current_depth + 1,
            type: :module
          }

          # Modules can include other modules
          module_source = File.read(module_file)
          module_ast = Parser.parse(module_source, module_file)
          if module_ast
            module_visitor = Visitor.new(file_path: module_file, inheritance_depth: current_depth + 1)
            module_visitor.process(module_ast)
            ancestors.concat(
              collect_ancestors(module_visitor, module_file, current_depth: current_depth + 1, visited: visited)
            )
          end
        end

        # Also handle prepended modules (same logic)
        visitor.prepended_modules.each do |mod|
          next if visited.include?(mod[:module_name])

          module_file = resolve(mod[:module_name], current_file)
          next unless module_file && File.exist?(module_file)

          visited.add(mod[:module_name])
          ancestors << {
            name: mod[:module_name],
            file: module_file,
            depth: current_depth + 1,
            type: :module
          }

          # Prepended modules can also include other modules
          module_source = File.read(module_file)
          module_ast = Parser.parse(module_source, module_file)
          if module_ast
            module_visitor = Visitor.new(file_path: module_file, inheritance_depth: current_depth + 1)
            module_visitor.process(module_ast)
            ancestors.concat(
              collect_ancestors(module_visitor, module_file, current_depth: current_depth + 1, visited: visited)
            )
          end
        end

        ancestors
      end

      private

      def resolve_by_convention(name, current_file)
        base_name = name
          .gsub(/::/, "/")
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase

        current_dir = File.dirname(current_file)

        patterns = [
          File.join(current_dir, "#{base_name}.rb"),
          File.join(current_dir, "..", "#{base_name}.rb"),
          File.join(current_dir, "concerns", "#{base_name}.rb"),
          File.join("app", "**", "#{base_name}.rb"),
          File.join("app", "**", "concerns", "#{base_name}.rb"),
          File.join("lib", "**", "#{base_name}.rb")
        ]

        patterns.each do |pattern|
          matches = Dir.glob(pattern)
          matches.reject! { |f| f.match?(%r{/(spec|test)/}) || f.end_with?("_spec.rb", "_test.rb") }
          return matches.first if matches.any?
        end

        nil
      end

      def resolve_by_grep(name)
        # Try both class and module definitions
        class_pattern = "^\\s*class\\s+#{Regexp.escape(name)}\\b"
        module_pattern = "^\\s*module\\s+#{Regexp.escape(name)}\\b"

        [class_pattern, module_pattern].each do |pattern|
          result = `grep -rl "#{pattern}" --include="*.rb" app lib 2>/dev/null`.strip
          next if result.empty?

          files = result.split("\n")
          files.reject! { |f| f.match?(%r{/(spec|test)/}) || f.end_with?("_spec.rb", "_test.rb") }
          return files.first if files.any?
        end

        nil
      end
    end
  end
end
