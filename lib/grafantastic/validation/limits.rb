# frozen_string_literal: true

module Grafantastic
  module Validation
    class Limits
      def initialize(config)
        @config = config
      end

      def validate!(signals)
        logs = signals.select(&:log?)
        metrics = signals.select(&:metric?)
        events = signals.select(&:event?)

        check_limit!(:logs, logs, @config.max_logs)
        check_limit!(:metrics, metrics, @config.max_metrics)
        check_limit!(:events, events, @config.max_events)

        total_panels = calculate_panel_count(logs, metrics, events)
        check_panel_limit!(total_panels, logs, metrics, events)
      end

      private

      def check_limit!(type, signals, limit)
        return if signals.size <= limit

        top_contributor = find_top_contributor(signals)

        raise LimitExceededError, format_error(type, signals.size, limit, top_contributor)
      end

      def check_panel_limit!(count, logs, metrics, events)
        return if count <= @config.max_panels

        all_signals = logs + metrics + events
        top_contributor = find_top_contributor(all_signals)

        raise LimitExceededError,
          "Panel limit exceeded: #{count} panels would be generated (max: #{@config.max_panels}). " \
          "Breakdown: #{logs.size} logs, #{metrics.size} metrics, #{events.size} events. " \
          "Top contributor: #{top_contributor}"
      end

      def calculate_panel_count(logs, metrics, events)
        # Each log = 1 panel
        # Each counter = 1 panel
        # Each histogram = 3 panels (p50, p95, p99)
        # Each gauge = 1 panel
        # Each event = 1 panel

        log_panels = logs.size

        metric_panels = metrics.sum do |m|
          case m.metadata[:metric_type]
          when :histogram
            3
          else
            1
          end
        end

        event_panels = events.size

        log_panels + metric_panels + event_panels
      end

      def find_top_contributor(signals)
        return "(none)" if signals.empty?

        counts = signals.group_by(&:defining_class).transform_values(&:size)
        top = counts.max_by { |_, v| v }

        "#{top[0]} (#{top[1]} signals)"
      end

      def format_error(type, found, limit, top_contributor)
        "#{type.to_s.capitalize} limit exceeded: found #{found}, max allowed #{limit}. " \
        "Top contributor: #{top_contributor}"
      end
    end
  end
end
