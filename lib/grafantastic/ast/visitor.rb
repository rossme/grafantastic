# frozen_string_literal: true

module Grafantastic
  module AST
    class Visitor
      attr_reader :file_path, :inheritance_depth, :class_definitions,
                  :log_calls, :metric_calls, :current_class

      # Logger method patterns
      LOG_RECEIVERS = %i[logger Rails].freeze
      LOG_METHODS = %i[debug info warn error fatal].freeze

      # Metric client patterns
      METRIC_RECEIVERS = %i[Prometheus StatsD Statsd Hesiod].freeze
      COUNTER_METHODS = %i[counter increment incr].freeze
      GAUGE_METHODS = %i[gauge set].freeze
      HISTOGRAM_METHODS = %i[histogram observe timing time].freeze
      SUMMARY_METHODS = %i[summary].freeze

      def initialize(file_path:, inheritance_depth:)
        @file_path = file_path
        @inheritance_depth = inheritance_depth
        @class_definitions = []
        @log_calls = []
        @metric_calls = []
        @current_class = nil
        @class_stack = []
      end

      def process(node)
        return unless node.is_a?(::Parser::AST::Node)

        case node.type
        when :class
          process_class(node)
        when :module
          process_module(node)
        when :send
          process_send(node)
        else
          node.children.each { |child| process(child) }
        end
      end

      private

      def process_class(node)
        class_name_node, parent_node, body = node.children

        class_name = extract_const_name(class_name_node)
        parent_name = parent_node ? extract_const_name(parent_node) : nil

        full_class_name = @class_stack.empty? ? class_name : "#{@class_stack.join("::")}::#{class_name}"

        @class_definitions << {
          name: full_class_name,
          parent: parent_name,
          file: @file_path
        }

        @class_stack.push(class_name)
        previous_class = @current_class
        @current_class = full_class_name

        process(body) if body

        @current_class = previous_class
        @class_stack.pop
      end

      def process_module(node)
        module_name_node, body = node.children
        module_name = extract_const_name(module_name_node)

        @class_stack.push(module_name)
        previous_class = @current_class
        @current_class = @class_stack.join("::")

        process(body) if body

        @current_class = previous_class
        @class_stack.pop
      end

      def process_send(node)
        receiver, method_name, *args = node.children

        if log_call?(receiver, method_name)
          record_log_call(node, receiver, method_name, args)
        elsif metric_call?(receiver, method_name, args)
          record_metric_call(node, receiver, method_name, args)
        end

        # Continue traversing
        node.children.each { |child| process(child) }
      end

      def log_call?(receiver, method_name)
        return false unless LOG_METHODS.include?(method_name)

        case receiver&.type
        when :send
          # logger.info or Rails.logger.info
          recv_recv, recv_method = receiver.children
          return true if recv_method == :logger
          return true if recv_recv&.type == :const && LOG_RECEIVERS.include?(extract_const_name(recv_recv)&.to_sym)
        when :lvar, :ivar
          # @logger.info or logger.info
          return receiver.children.first.to_s.include?("logger")
        end

        false
      end

      def metric_call?(receiver, method_name, args)
        return false unless receiver

        # Direct calls: StatsD.increment("metric")
        if receiver.type == :const
          const_name = extract_const_name(receiver)&.to_sym
          return METRIC_RECEIVERS.include?(const_name)
        end

        # Chained calls: Prometheus.counter(:name).increment
        if receiver.type == :send
          recv_recv, recv_method, *recv_args = receiver.children
          if recv_recv&.type == :const
            const_name = extract_const_name(recv_recv)&.to_sym
            return METRIC_RECEIVERS.include?(const_name)
          end
        end

        false
      end

      def record_log_call(node, receiver, method_name, args)
        event_name = extract_log_event_name(args)

        @log_calls << {
          level: method_name.to_s,
          event_name: event_name,
          defining_class: @current_class || "(top-level)",
          line: node.loc&.line
        }
      end

      def record_metric_call(node, receiver, method_name, args)
        metric_info = extract_metric_info(receiver, method_name, args)
        return unless metric_info

        @metric_calls << {
          name: metric_info[:name],
          metric_type: metric_info[:type],
          defining_class: @current_class || "(top-level)",
          line: node.loc&.line
        }
      end

      def extract_log_event_name(args)
        return nil if args.empty?

        first_arg = args.first
        case first_arg&.type
        when :str
          # Literal string - derive stable identifier
          message = first_arg.children.first
          derive_event_name(message)
        when :sym
          # Symbol - use directly
          first_arg.children.first.to_s
        when :dstr
          # Interpolated string - use first static part
          static_parts = first_arg.children.select { |c| c.type == :str }
          message = static_parts.map { |s| s.children.first }.join
          derive_event_name(message)
        else
          nil
        end
      end

      def derive_event_name(message)
        return nil if message.nil? || message.empty?

        # Create stable identifier from message
        sanitized = message
          .downcase
          .gsub(/[^a-z0-9]+/, "_")
          .gsub(/^_|_$/, "")
          .slice(0, 50)

        sanitized.empty? ? nil : sanitized
      end

      def extract_metric_info(receiver, method_name, args)
        # Handle chained calls: Prometheus.counter(:name).increment
        if receiver.type == :send
          recv_recv, recv_method, *recv_args = receiver.children
          metric_name = extract_metric_name(recv_args)
          metric_type = infer_metric_type(recv_method)
          return { name: metric_name, type: metric_type } if metric_name
        end

        # Handle direct calls: StatsD.increment("name")
        if receiver.type == :const
          metric_name = extract_metric_name(args)
          metric_type = infer_metric_type(method_name)
          return { name: metric_name, type: metric_type } if metric_name
        end

        nil
      end

      def extract_metric_name(args)
        return nil if args.empty?

        first_arg = args.first
        case first_arg&.type
        when :str
          first_arg.children.first
        when :sym
          first_arg.children.first.to_s
        else
          nil
        end
      end

      def infer_metric_type(method_name)
        return :counter if COUNTER_METHODS.include?(method_name)
        return :gauge if GAUGE_METHODS.include?(method_name)
        return :histogram if HISTOGRAM_METHODS.include?(method_name)
        return :summary if SUMMARY_METHODS.include?(method_name)

        :counter # Default
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
