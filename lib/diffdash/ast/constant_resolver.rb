# frozen_string_literal: true

module Diffdash
  module AST
    # Resolves metric constant definitions to their underlying metric names.
    #
    # Handles patterns like:
    #   RequestTotal = Hesiod.register_counter("request_total")
    #   CACHE_HIT = StatsD.counter("cache.hit")
    #
    # Then resolves calls like:
    #   Metrics::RequestTotal.increment → "request_total"
    #   CACHE_HIT.increment → "cache.hit"
    #
    class ConstantResolver
      # Methods that register/create metric objects
      REGISTRATION_METHODS = %i[
        register_counter register_gauge register_histogram register_summary
        counter gauge histogram summary
      ].freeze

      # Map registration method to metric type
      METHOD_TO_TYPE = {
        register_counter: :counter,
        register_gauge: :gauge,
        register_histogram: :histogram,
        register_summary: :summary,
        counter: :counter,
        gauge: :gauge,
        histogram: :histogram,
        summary: :summary
      }.freeze

      attr_reader :constant_map

      def initialize
        @constant_map = {}
      end

      # Scan a file for metric constant definitions
      # @param source [String] Ruby source code
      # @param file_path [String] Path to file (for namespace context)
      def scan(source, file_path)
        ast = Parser.parse(source, file_path)
        return unless ast

        scan_node(ast, [])
      end

      # Resolve a constant name to its metric info
      # @param constant_name [String] e.g., "Metrics::RequestTotal"
      # @return [Hash, nil] { name: "request_total", type: :counter }
      def resolve(constant_name)
        @constant_map[constant_name]
      end

      private

      def scan_node(node, namespace)
        return unless node.is_a?(::Parser::AST::Node)

        case node.type
        when :module
          module_name = extract_const_name(node.children[0])
          new_namespace = namespace + [module_name]
          node.children[1..].each { |child| scan_node(child, new_namespace) }
        when :class
          class_name = extract_const_name(node.children[0])
          new_namespace = namespace + [class_name]
          node.children[1..].each { |child| scan_node(child, new_namespace) }
        when :casgn
          process_constant_assignment(node, namespace)
        when :begin
          node.children.each { |child| scan_node(child, namespace) }
        else
          node.children.each { |child| scan_node(child, namespace) }
        end
      end

      def process_constant_assignment(node, namespace)
        # casgn structure: [parent_const, const_name, value]
        parent_const, const_name, value = node.children
        return unless value&.type == :send

        receiver, method_name, *args = value.children
        return unless REGISTRATION_METHODS.include?(method_name)

        metric_name = extract_metric_name(args)
        return unless metric_name

        # Build full constant name
        full_name = if parent_const
                      "#{extract_const_name(parent_const)}::#{const_name}"
                    elsif namespace.any?
                      "#{namespace.join('::')}::#{const_name}"
                    else
                      const_name.to_s
                    end

        @constant_map[full_name] = {
          name: metric_name,
          type: METHOD_TO_TYPE[method_name] || :counter
        }
      end

      def extract_metric_name(args)
        return nil if args.empty?

        first_arg = args.first
        case first_arg&.type
        when :str
          first_arg.children.first
        when :sym
          first_arg.children.first.to_s
        end
      end

      def extract_const_name(node)
        return nil unless node

        case node.type
        when :const
          parent, name = node.children
          if parent
            "#{extract_const_name(parent)}::#{name}"
          else
            name.to_s
          end
        else
          nil
        end
      end
    end
  end
end
