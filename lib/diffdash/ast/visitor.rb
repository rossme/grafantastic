# frozen_string_literal: true

module Diffdash
  module AST
    # Traverses a Ruby AST and extracts observability signals.
    #
    # Collects:
    # - Log calls (logger.info, Rails.logger.warn, etc.)
    # - Metric calls (StatsD.increment, Prometheus.counter, Hesiod, etc.)
    # - Class/module definitions and their inheritance relationships
    # - Module inclusions (include, prepend, extend)
    #
    # The visitor walks the AST recursively, recording relevant method calls
    # and their metadata (class context, line number, log level, metric type).
    #
    # @example
    #   ast = Parser.parse(source, file_path)
    #   visitor = Visitor.new(file_path: file_path, inheritance_depth: 0)
    #   visitor.process(ast)
    #   visitor.log_calls      # => [{ level: "info", event_name: "...", ... }]
    #   visitor.metric_calls   # => [{ name: "...", metric_type: :counter, ... }]
    class Visitor
      attr_reader :file_path, :inheritance_depth, :class_definitions,
                  :module_definitions, :log_calls, :metric_calls,
                  :dynamic_metric_calls, :current_class,
                  :included_modules, :prepended_modules, :extended_modules

      # Logger method patterns
      LOG_RECEIVERS = %i[logger Rails].freeze
      LOG_METHODS = %i[debug info warn error fatal unknown].freeze
      LOG_GENERIC_METHODS = %i[add log].freeze # Generic logging methods that take severity as first arg

      # Metric client patterns
      METRIC_RECEIVERS = %i[Prometheus StatsD Statsd Hesiod Datadog DogStatsD].freeze
      COUNTER_METHODS = %i[counter increment incr].freeze
      GAUGE_METHODS = %i[gauge set].freeze
      HISTOGRAM_METHODS = %i[histogram observe timing time].freeze
      SUMMARY_METHODS = %i[summary].freeze

      def initialize(file_path:, inheritance_depth:)
        @file_path = file_path
        @inheritance_depth = inheritance_depth
        @class_definitions = []
        @module_definitions = []
        @log_calls = []
        @metric_calls = []
        @dynamic_metric_calls = []
        @included_modules = []
        @prepended_modules = []
        @extended_modules = []
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

        full_module_name = @class_stack.empty? ? module_name : "#{@class_stack.join("::")}::#{module_name}"

        @module_definitions << {
          name: full_module_name,
          file: @file_path
        }

        @class_stack.push(module_name)
        previous_class = @current_class
        @current_class = full_module_name

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
        elsif module_inclusion?(receiver, method_name)
          record_module_inclusion(method_name, args)
        end

        # Continue traversing
        node.children.each { |child| process(child) }
      end

      def module_inclusion?(receiver, method_name)
        # include/prepend/extend at class/module level (receiver is nil)
        receiver.nil? && %i[include prepend extend].include?(method_name)
      end

      def record_module_inclusion(method_name, args)
        args.each do |arg|
          module_name = extract_const_name(arg)
          next unless module_name

          entry = {
            module_name: module_name,
            including_class: @current_class,
            file: @file_path
          }

          case method_name
          when :include
            @included_modules << entry
          when :prepend
            @prepended_modules << entry
          when :extend
            @extended_modules << entry
          end
        end
      end

      def log_call?(receiver, method_name)
        # Check if it's a standard log method or generic method
        return false unless LOG_METHODS.include?(method_name) || LOG_GENERIC_METHODS.include?(method_name)

        case receiver&.type
        when :send
          # logger.info or Rails.logger.info
          recv_recv, recv_method = receiver.children
          return true if recv_method == :logger
          return true if recv_recv&.type == :const && LOG_RECEIVERS.include?(extract_const_name(recv_recv)&.to_sym)
        when :lvar, :ivar, :cvar
          # @logger.info or logger.info or @@logger.info
          return receiver.children.first.to_s.include?("logger")
        when :const
          # LOG.info or LOGGER.info (constant logger objects)
          const_name = extract_const_name(receiver)
          # Match common logger constant names
          return const_name&.match?(/\b(log|logger)\b/i)
        end

        false
      end

      # Methods that create metric objects (Prometheus factory pattern)
      METRIC_FACTORY_METHODS = %i[counter gauge histogram summary].freeze
      # Methods that perform metric actions
      METRIC_ACTION_METHODS = %i[increment incr decrement decr set observe time timing].freeze
      # StatsD-style action methods (called directly, not via factory pattern)
      STATSD_ACTION_METHODS = %i[increment incr decrement decr gauge set timing time histogram distribution emit].freeze
      # Receivers that use factory pattern (Prometheus.counter(:name).increment)
      FACTORY_PATTERN_RECEIVERS = %i[Prometheus].freeze
      # Receivers that use direct action pattern (StatsD.increment("name"))
      DIRECT_ACTION_RECEIVERS = %i[StatsD Statsd Datadog DogStatsD Hesiod].freeze

      def metric_call?(receiver, method_name, args)
        return false unless receiver

        # Direct calls: StatsD.increment("metric"), Datadog.gauge("metric", val)
        if receiver.type == :const
          const_name = extract_const_name(receiver)&.to_sym
          return false unless METRIC_RECEIVERS.include?(const_name)

          # For direct-action receivers (StatsD, Datadog, etc.), accept their action methods
          if DIRECT_ACTION_RECEIVERS.include?(const_name)
            return STATSD_ACTION_METHODS.include?(method_name)
          end

          # For factory-pattern receivers (Prometheus), reject factory methods as direct calls
          return !METRIC_FACTORY_METHODS.include?(method_name)
        end

        # Chained calls: Prometheus.counter(:name).increment
        # Match when receiver is a send (factory call) on a metric receiver
        if receiver.type == :send
          recv_recv, recv_method, *recv_args = receiver.children
          if recv_recv&.type == :const
            const_name = extract_const_name(recv_recv)&.to_sym
            return METRIC_RECEIVERS.include?(const_name) && METRIC_FACTORY_METHODS.include?(recv_method)
          end
        end

        false
      end

      def record_log_call(node, receiver, method_name, args)
        # Handle generic methods (add, log) that take severity as first arg
        if LOG_GENERIC_METHODS.include?(method_name)
          level, *message_args = extract_generic_log_info(args)
          event_name = extract_log_event_name(message_args)
          
          @log_calls << {
            level: level || "info",
            event_name: event_name,
            defining_class: @current_class || "(top-level)",
            line: node.loc&.line
          }
        else
          # Standard logger.info/debug/etc style calls
          event_name = extract_log_event_name(args)

          @log_calls << {
            level: method_name.to_s,
            event_name: event_name,
            defining_class: @current_class || "(top-level)",
            line: node.loc&.line
          }
        end
      end
      
      def extract_generic_log_info(args)
        return [nil] if args.empty?
        
        first_arg = args.first
        # Generic log methods can be called as:
        # logger.add(Logger::INFO, "message")
        # logger.add(:info, "message")
        # logger.add("message") - defaults to info
        if first_arg&.type == :sym && LOG_METHODS.include?(first_arg.children.first)
          level = first_arg.children.first.to_s
          [level, *args[1..-1]]
        elsif first_arg&.type == :const
          # Handle Logger::INFO, Logger::DEBUG, etc.
          const_name = extract_const_name(first_arg)
          if const_name&.match?(/^Logger::/)
            level = const_name.split("::").last.downcase
            [level, *args[1..-1]]
          else
            ["info", *args]
          end
        elsif first_arg&.type == :int
          # Numeric severity levels (0=debug, 1=info, 2=warn, 3=error, 4=fatal, 5=unknown)
          severity_map = ["debug", "info", "warn", "error", "fatal", "unknown"]
          severity_num = first_arg.children.first
          level = severity_map[severity_num] || "info"
          [level, *args[1..-1]]
        else
          ["info", *args]
        end
      end

      def record_metric_call(node, receiver, method_name, args)
        metric_info = extract_metric_info(receiver, method_name, args)

        if metric_info && metric_info[:name]
          @metric_calls << {
            name: metric_info[:name],
            metric_type: metric_info[:type],
            defining_class: @current_class || "(top-level)",
            line: node.loc&.line
          }
        elsif metric_info && metric_info[:dynamic]
          @dynamic_metric_calls << {
            metric_type: metric_info[:type],
            defining_class: @current_class || "(top-level)",
            line: node.loc&.line,
            receiver: metric_info[:receiver]
          }
        end
      end

      def extract_log_event_name(args)
        return nil if args.empty?

        first_arg = args.first
        case first_arg&.type
        when :str
          # Literal string - use raw message for exact matching
          first_arg.children.first
        when :sym
          # Symbol - use directly
          first_arg.children.first.to_s
        when :dstr
          # Interpolated string - extract static parts for matching
          # e.g., "Loaded widget #{id}" -> "Loaded widget "
          static_parts = first_arg.children.select { |c| c.type == :str }
          message = static_parts.map { |s| s.children.first }.join
          # Return the static parts as-is for Grafana matching
          # This allows queries like |= "Loaded widget " to match all instances
          message.empty? ? nil : message
        else
          nil
        end
      end


      def extract_metric_info(receiver, method_name, args)
        # Handle chained calls: Prometheus.counter(:name).increment
        if receiver.type == :send
          recv_recv, recv_method, *recv_args = receiver.children
          metric_name = extract_metric_name(recv_args)
          metric_type = infer_metric_type(recv_method)

          if metric_name
            return { name: metric_name, type: metric_type }
          elsif recv_recv&.type == :const
            # Dynamic metric name detected
            receiver_name = extract_const_name(recv_recv)
            return { dynamic: true, type: metric_type, receiver: receiver_name }
          end
        end

        # Handle direct calls: StatsD.increment("name")
        if receiver.type == :const
          metric_name = extract_metric_name(args)
          metric_type = infer_metric_type(method_name)

          if metric_name
            return { name: metric_name, type: metric_type }
          else
            # Dynamic metric name detected
            receiver_name = extract_const_name(receiver)
            return { dynamic: true, type: metric_type, receiver: receiver_name }
          end
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
        return :histogram if HISTOGRAM_METHODS.include?(method_name) || method_name == :distribution
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
