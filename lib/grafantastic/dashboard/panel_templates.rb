# frozen_string_literal: true

module Grafantastic
  module Dashboard
    class PanelTemplates
      class << self
        def log_panel(signal, panel_id, grid_pos)
          {
            id: panel_id,
            type: "logs",
            title: "Log: #{truncate(signal.name, 30)}",
            description: "Source: #{signal.defining_class} (#{relative_path(signal.source_file)})",
            gridPos: grid_pos,
            targets: [
              {
                datasource: { type: "loki", uid: "${datasource_loki}" },
                expr: build_log_query(signal),
                refId: "A"
              }
            ],
            options: {
              showTime: true,
              showLabels: true,
              showCommonLabels: false,
              wrapLogMessage: true,
              prettifyLogMessage: false,
              enableLogDetails: true,
              sortOrder: "Descending"
            }
          }
        end

        def counter_panel(signal, panel_id, grid_pos)
          {
            id: panel_id,
            type: "timeseries",
            title: "Counter: #{truncate(signal.name, 25)}",
            description: "Source: #{signal.defining_class}",
            gridPos: grid_pos,
            targets: [
              {
                datasource: { type: "prometheus", uid: "${datasource}" },
                expr: "sum(rate(#{sanitize_metric_name(signal.name)}[$__rate_interval])) by (service)",
                legendFormat: "{{service}}",
                refId: "A"
              }
            ],
            fieldConfig: {
              defaults: {
                unit: "ops",
                custom: {
                  drawStyle: "line",
                  lineInterpolation: "smooth",
                  fillOpacity: 10
                }
              }
            },
            options: {
              legend: { displayMode: "list", placement: "bottom" }
            }
          }
        end

        def gauge_panel(signal, panel_id, grid_pos)
          {
            id: panel_id,
            type: "timeseries",
            title: "Gauge: #{truncate(signal.name, 25)}",
            description: "Source: #{signal.defining_class}",
            gridPos: grid_pos,
            targets: [
              {
                datasource: { type: "prometheus", uid: "${datasource}" },
                expr: "#{sanitize_metric_name(signal.name)}{service=\"$service\", env=\"$env\"}",
                legendFormat: "{{instance}}",
                refId: "A"
              }
            ],
            fieldConfig: {
              defaults: {
                custom: {
                  drawStyle: "line",
                  lineInterpolation: "smooth",
                  fillOpacity: 5
                }
              }
            }
          }
        end

        def histogram_panels(signal, start_panel_id, start_grid_pos)
          panels = []
          percentiles = [
            { p: "0.5", label: "p50" },
            { p: "0.95", label: "p95" },
            { p: "0.99", label: "p99" }
          ]

          percentiles.each_with_index do |pct, idx|
            grid_pos = {
              x: (start_grid_pos[:x] + (idx * 8)) % 24,
              y: start_grid_pos[:y] + ((start_grid_pos[:x] + (idx * 8)) / 24) * 8,
              w: 8,
              h: 8
            }

            panels << {
              id: start_panel_id + idx,
              type: "timeseries",
              title: "#{truncate(signal.name, 20)} (#{pct[:label]})",
              description: "Source: #{signal.defining_class}",
              gridPos: grid_pos,
              targets: [
                {
                  datasource: { type: "prometheus", uid: "${datasource}" },
                  expr: "histogram_quantile(#{pct[:p]}, sum(rate(#{sanitize_metric_name(signal.name)}_bucket[$__rate_interval])) by (le, service))",
                  legendFormat: "{{service}} #{pct[:label]}",
                  refId: "A"
                }
              ],
              fieldConfig: {
                defaults: {
                  unit: "s",
                  custom: {
                    drawStyle: "line",
                    lineInterpolation: "smooth",
                    fillOpacity: 10
                  }
                }
              }
            }
          end

          panels
        end

        def empty_dashboard_panel
          {
            id: 1,
            type: "text",
            title: "No Signals Detected",
            gridPos: { x: 0, y: 0, w: 24, h: 4 },
            options: {
              mode: "markdown",
              content: "# No observability signals detected in this PR.\n\n" \
                       "This dashboard was auto-generated but found no logs, metrics, or events " \
                       "in the changed Ruby files."
            }
          }
        end

        private

        def build_log_query(signal)
          event_filter = signal.name ? " |= `#{signal.name}`" : ""
          "{service=\"$service\", env=\"$env\"}#{event_filter}"
        end

        def sanitize_metric_name(name)
          name.to_s.gsub(/[^a-zA-Z0-9_:]/, "_")
        end

        def truncate(str, length)
          str.to_s.length > length ? "#{str[0, length - 3]}..." : str.to_s
        end

        def relative_path(path)
          path.sub(%r{^.*/app/}, "app/").sub(%r{^.*/lib/}, "lib/")
        end
      end
    end
  end
end
