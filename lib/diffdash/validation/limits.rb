# frozen_string_literal: true

module Diffdash
  module Validation
    class Limits
      attr_reader :warnings

      def initialize(config)
        @config = config
        @warnings = []
      end

      def truncate_and_validate(signals)
        logs = signals.select(&:log?)
        metrics = signals.select(&:metric?)
        events = signals.select(&:event?)

        # Truncate each type if needed
        logs = truncate_signals(:logs, logs, @config.max_logs)
        metrics = truncate_signals(:metrics, metrics, @config.max_metrics)
        events = truncate_signals(:events, events, @config.max_events)

        # Check panel limit and truncate further if needed
        truncated = truncate_by_panel_limit(logs, metrics, events)

        truncated[:logs] + truncated[:metrics] + truncated[:events]
      end

      private

      def truncate_signals(type, signals, limit)
        return signals if signals.size <= limit

        excluded_count = signals.size - limit
        @warnings << "#{excluded_count} #{type} not added to dashboard (limit: #{limit})"

        signals.take(limit)
      end

      def truncate_by_panel_limit(logs, metrics, events)
        total_panels = calculate_panel_count(logs, metrics, events)
        return { logs: logs, metrics: metrics, events: events } if total_panels <= @config.max_panels

        # Need to reduce panels - prioritize by removing least critical signals
        result = { logs: logs.dup, metrics: metrics.dup, events: events.dup }
        panels_to_remove = total_panels - @config.max_panels

        # Remove logs first (easiest to reduce)
        while panels_to_remove > 0 && result[:logs].any?
          result[:logs].pop
          panels_to_remove -= 1
        end

        # Then metrics (but histograms cost 3 panels each)
        while panels_to_remove > 0 && result[:metrics].any?
          removed = result[:metrics].pop
          panel_cost = removed.metadata[:metric_type] == :histogram ? 3 : 1
          panels_to_remove -= panel_cost
        end

        # Finally events if still over
        while panels_to_remove > 0 && result[:events].any?
          result[:events].pop
          panels_to_remove -= 1
        end

        # Calculate what was excluded
        excluded_logs = logs.size - result[:logs].size
        excluded_metrics = metrics.size - result[:metrics].size
        excluded_events = events.size - result[:events].size

        if excluded_logs > 0 || excluded_metrics > 0 || excluded_events > 0
          parts = []
          parts << "#{excluded_logs} logs" if excluded_logs > 0
          parts << "#{excluded_metrics} metrics" if excluded_metrics > 0
          parts << "#{excluded_events} events" if excluded_events > 0
          @warnings << "#{parts.join(", ")} not added to dashboard (panel limit: #{@config.max_panels})"
        end

        result
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
