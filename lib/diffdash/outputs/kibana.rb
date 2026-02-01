# frozen_string_literal: true

module Diffdash
  module Outputs
    # Kibana output adapter.
    # Translates SignalQuery intent into Kibana dashboard JSON (NDJSON format).
    #
    # Kibana dashboards use the Saved Objects API which expects NDJSON format
    # (newline-delimited JSON) for import/export.
    class Kibana < Base
      def initialize(title:, dry_run: false, verbose: false, index_pattern: nil)
        @title = title
        @dry_run = dry_run
        @verbose = verbose
        @index_pattern = index_pattern || ENV['DIFFDASH_KIBANA_INDEX_PATTERN'] || 'logs-*'
      end

      # Render SignalBundle into Kibana dashboard payload
      # @return [Hash] Kibana saved objects structure
      def render(signal_bundle)
        dashboard_id = generate_id('dashboard')

        {
          dashboard: build_dashboard(signal_bundle, dashboard_id),
          visualizations: build_visualizations(signal_bundle),
          index_pattern: build_index_pattern
        }
      end

      def upload(payload)
        ndjson_content = build_ndjson(payload)

        return export_to_file(payload, ndjson_content) if @dry_run

        # Try API upload if credentials are configured
        if kibana_configured?
          upload_via_api(payload, ndjson_content)
        else
          export_to_file(payload, ndjson_content)
        end
      end

      private

      def kibana_configured?
        ENV['DIFFDASH_KIBANA_URL'] &&
          (ENV['DIFFDASH_KIBANA_API_KEY'] ||
           (ENV['DIFFDASH_KIBANA_USERNAME'] && ENV['DIFFDASH_KIBANA_PASSWORD']))
      end

      def build_ndjson(payload)
        ndjson_lines = []

        # Add index pattern
        ndjson_lines << JSON.generate(payload[:index_pattern])

        # Add visualizations
        payload[:visualizations].each do |viz|
          ndjson_lines << JSON.generate(viz)
        end

        # Add dashboard
        ndjson_lines << JSON.generate(payload[:dashboard])

        ndjson_lines.join("\n")
      end

      def upload_via_api(payload, ndjson_content)
        client = Clients::Kibana.new
        log_verbose('Validating Kibana connection...')
        client.health_check!
        log_verbose("Connected to Kibana at #{client.url}")

        result = client.import_saved_objects(ndjson_content)

        if result[:success]
          log_verbose("Dashboard imported successfully (#{result[:successCount]} objects)")
        else
          log_verbose("Import completed with errors: #{result[:errors]}")
        end

        { payload: payload, url: result[:url] }
      end

      def export_to_file(payload, ndjson_content)
        output_file = 'diffdash-kibana-dashboard.ndjson'

        if @dry_run
          log_verbose('Dry run - dashboard NDJSON not written to file')
        else
          File.write(output_file, ndjson_content)
          log_verbose("Kibana dashboard NDJSON written to: #{output_file}")
          log_verbose('Import via: Kibana → Stack Management → Saved Objects → Import')
          log_verbose('Or set DIFFDASH_KIBANA_URL and credentials for API upload')
        end

        { payload: payload, url: nil, file: output_file }
      end

      def build_dashboard(signal_bundle, dashboard_id)
        viz_references = build_visualization_references(signal_bundle)
        panels = build_panels(signal_bundle)

        {
          type: 'dashboard',
          id: dashboard_id,
          attributes: {
            title: @title,
            description: build_description(signal_bundle),
            panelsJSON: JSON.generate(panels),
            optionsJSON: JSON.generate({
                                         useMargins: true,
                                         syncColors: false,
                                         hidePanelTitles: false
                                       }),
            timeRestore: true,
            timeTo: 'now',
            timeFrom: 'now-30m',
            refreshInterval: {
              pause: false,
              value: 30_000
            },
            kibanaSavedObjectMeta: {
              searchSourceJSON: JSON.generate({
                                                query: { query: '', language: 'kuery' },
                                                filter: []
                                              })
            }
          },
          references: viz_references
        }
      end

      def build_visualizations(signal_bundle)
        visualizations = []

        # Log visualizations
        signal_bundle.logs.each_with_index do |signal, idx|
          visualizations << log_visualization(signal, idx)
        end

        # Metric visualizations
        signal_bundle.metrics.each_with_index do |signal, idx|
          offset = signal_bundle.logs.size
          visualizations << case signal.metadata[:metric_type]
                            when :counter
                              counter_visualization(signal, offset + idx)
                            when :gauge
                              gauge_visualization(signal, offset + idx)
                            when :histogram
                              histogram_visualization(signal, offset + idx)
                            else
                              counter_visualization(signal, offset + idx)
                            end
        end

        visualizations
      end

      def build_panels(signal_bundle)
        panels = []
        panel_idx = 0

        # Log panels (use search type to show actual log entries)
        signal_bundle.logs.each_with_index do |_signal, _idx|
          panels << {
            version: '8.0.0',
            type: 'search',
            gridData: grid_position(panel_idx),
            panelIndex: panel_idx.to_s,
            embeddableConfig: {},
            panelRefName: "panel_#{panel_idx}"
          }
          panel_idx += 1
        end

        # Metric panels (use visualization type)
        signal_bundle.metrics.each_with_index do |_signal, _idx|
          panels << {
            version: '8.0.0',
            type: 'visualization',
            gridData: grid_position(panel_idx),
            panelIndex: panel_idx.to_s,
            embeddableConfig: {},
            panelRefName: "panel_#{panel_idx}"
          }
          panel_idx += 1
        end

        panels
      end

      def build_visualization_references(signal_bundle)
        references = []
        log_count = signal_bundle.logs.size

        # Log references (search type)
        log_count.times do |idx|
          references << {
            name: "panel_#{idx}",
            type: 'search',
            id: generate_id("search-#{idx}")
          }
        end

        # Metric references (visualization type)
        signal_bundle.metrics.size.times do |idx|
          references << {
            name: "panel_#{log_count + idx}",
            type: 'visualization',
            id: generate_id("viz-#{log_count + idx}")
          }
        end

        references
      end

      def log_visualization(signal, idx)
        generate_id("viz-#{idx}")
        search_id = generate_id("search-#{idx}")

        # Use a saved search which shows actual log entries
        {
          type: 'search',
          id: search_id,
          attributes: {
            title: "Log: #{truncate(signal.name, 30)}",
            description: "Source: #{signal.defining_class}",
            columns: ['message', '@timestamp'],
            sort: [['@timestamp', 'desc']],
            kibanaSavedObjectMeta: {
              searchSourceJSON: JSON.generate({
                                                query: {
                                                  query: build_log_query(signal),
                                                  language: 'kuery'
                                                },
                                                filter: [],
                                                indexRefName: 'kibanaSavedObjectMeta.searchSourceJSON.index',
                                                highlightAll: true,
                                                version: true
                                              })
            }
          },
          references: [
            {
              name: 'kibanaSavedObjectMeta.searchSourceJSON.index',
              type: 'index-pattern',
              id: generate_id('index-pattern')
            }
          ]
        }
      end

      def counter_visualization(signal, idx)
        viz_id = generate_id("viz-#{idx}")

        {
          type: 'visualization',
          id: viz_id,
          attributes: {
            title: "Counter: #{truncate(signal.name, 25)}",
            description: "Source: #{signal.defining_class}",
            visState: JSON.generate({
                                      title: "Counter: #{signal.name}",
                                      type: 'line',
                                      aggs: [
                                        {
                                          id: '1',
                                          enabled: true,
                                          type: 'sum',
                                          schema: 'metric',
                                          params: {
                                            field: sanitize_metric_name(signal.name)
                                          }
                                        },
                                        {
                                          id: '2',
                                          enabled: true,
                                          type: 'date_histogram',
                                          schema: 'segment',
                                          params: {
                                            field: '@timestamp',
                                            interval: 'auto'
                                          }
                                        }
                                      ],
                                      params: {
                                        type: 'line',
                                        grid: { categoryLines: false },
                                        categoryAxes: [{ id: 'CategoryAxis-1', type: 'category', position: 'bottom' }],
                                        valueAxes: [{ id: 'ValueAxis-1', type: 'value', position: 'left' }]
                                      }
                                    }),
            uiStateJSON: '{}',
            kibanaSavedObjectMeta: {
              searchSourceJSON: JSON.generate({
                                                query: { query: '', language: 'kuery' },
                                                filter: [],
                                                indexRefName: 'kibanaSavedObjectMeta.searchSourceJSON.index'
                                              })
            }
          },
          references: [
            {
              name: 'kibanaSavedObjectMeta.searchSourceJSON.index',
              type: 'index-pattern',
              id: generate_id('index-pattern')
            }
          ]
        }
      end

      def gauge_visualization(signal, idx)
        viz_id = generate_id("viz-#{idx}")

        {
          type: 'visualization',
          id: viz_id,
          attributes: {
            title: "Gauge: #{truncate(signal.name, 25)}",
            description: "Source: #{signal.defining_class}",
            visState: JSON.generate({
                                      title: "Gauge: #{signal.name}",
                                      type: 'gauge',
                                      aggs: [
                                        {
                                          id: '1',
                                          enabled: true,
                                          type: 'avg',
                                          schema: 'metric',
                                          params: {
                                            field: sanitize_metric_name(signal.name)
                                          }
                                        }
                                      ],
                                      params: {
                                        type: 'gauge',
                                        addTooltip: true,
                                        addLegend: true,
                                        gauge: {
                                          verticalSplit: false,
                                          autoExtend: false,
                                          percentageMode: false,
                                          gaugeType: 'Arc',
                                          gaugeStyle: 'Full',
                                          backStyle: 'Full',
                                          orientation: 'vertical',
                                          useRanges: false,
                                          colorSchema: 'Green to Red',
                                          gaugeColorMode: 'Labels',
                                          colorsRange: [{ from: 0, to: 100 }],
                                          invertColors: false,
                                          labels: { show: true, color: 'black' },
                                          scale: { show: false, labels: false, color: '#333' },
                                          type: 'meter',
                                          style: { subText: '', fontSize: 60 }
                                        }
                                      }
                                    }),
            uiStateJSON: '{}',
            kibanaSavedObjectMeta: {
              searchSourceJSON: JSON.generate({
                                                query: { query: '', language: 'kuery' },
                                                filter: [],
                                                indexRefName: 'kibanaSavedObjectMeta.searchSourceJSON.index'
                                              })
            }
          },
          references: [
            {
              name: 'kibanaSavedObjectMeta.searchSourceJSON.index',
              type: 'index-pattern',
              id: generate_id('index-pattern')
            }
          ]
        }
      end

      def histogram_visualization(signal, idx)
        viz_id = generate_id("viz-#{idx}")

        {
          type: 'visualization',
          id: viz_id,
          attributes: {
            title: "Histogram: #{truncate(signal.name, 22)}",
            description: "Source: #{signal.defining_class}",
            visState: JSON.generate({
                                      title: "Histogram: #{signal.name}",
                                      type: 'histogram',
                                      aggs: [
                                        {
                                          id: '1',
                                          enabled: true,
                                          type: 'count',
                                          schema: 'metric'
                                        },
                                        {
                                          id: '2',
                                          enabled: true,
                                          type: 'histogram',
                                          schema: 'segment',
                                          params: {
                                            field: sanitize_metric_name(signal.name),
                                            interval: 'auto'
                                          }
                                        }
                                      ],
                                      params: {
                                        type: 'histogram',
                                        grid: { categoryLines: false },
                                        categoryAxes: [{ id: 'CategoryAxis-1', type: 'category', position: 'bottom' }],
                                        valueAxes: [{ id: 'ValueAxis-1', type: 'value', position: 'left' }]
                                      }
                                    }),
            uiStateJSON: '{}',
            kibanaSavedObjectMeta: {
              searchSourceJSON: JSON.generate({
                                                query: { query: '', language: 'kuery' },
                                                filter: [],
                                                indexRefName: 'kibanaSavedObjectMeta.searchSourceJSON.index'
                                              })
            }
          },
          references: [
            {
              name: 'kibanaSavedObjectMeta.searchSourceJSON.index',
              type: 'index-pattern',
              id: generate_id('index-pattern')
            }
          ]
        }
      end

      def build_index_pattern
        {
          type: 'index-pattern',
          id: generate_id('index-pattern'),
          attributes: {
            title: @index_pattern,
            timeFieldName: '@timestamp'
          },
          references: []
        }
      end

      def build_description(signal_bundle)
        log_count = signal_bundle.logs&.size || 0
        metric_count = signal_bundle.metrics&.size || 0
        branch = signal_bundle.metadata.dig(:change_set, :branch_name) || 'unknown'

        "Auto-generated by diffdash. Branch: #{branch}. " \
          "Detected #{log_count} log(s) and #{metric_count} metric(s)."
      end

      def build_log_query(signal)
        # Kibana Query Language (KQL) format
        signal.name ? "message:\"#{escape_kql(signal.name)}\"" : '*'
      end

      def escape_kql(value)
        # Escape special KQL characters
        value.to_s.gsub(/([\\"])/, '\\\\\1')
      end

      def grid_position(idx)
        # 48-unit grid, 2 panels per row (24 units each)
        col = (idx % 2) * 24
        row = (idx / 2) * 15

        {
          x: col,
          y: row,
          w: 24,
          h: 15,
          i: idx.to_s
        }
      end

      def generate_id(prefix)
        require 'digest'
        Digest::SHA256.hexdigest("#{@title}-#{prefix}")[0, 16]
      end

      def sanitize_metric_name(name)
        name.to_s.downcase.gsub(/[^a-z0-9_]/, '_')
      end

      def truncate(str, length)
        str.to_s.length > length ? "#{str[0, length - 3]}..." : str.to_s
      end

      def log_verbose(message)
        warn "[diffdash] #{message}" if @verbose
      end
    end
  end
end
