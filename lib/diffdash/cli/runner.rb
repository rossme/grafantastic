# frozen_string_literal: true

module Diffdash
  module CLI
    # Thin CLI glue. Orchestrates engine + output adapters.
    class Runner
      VALID_OPTIONS = %w[--dry-run --verbose -v --help -h].freeze
      VALID_SUBCOMMANDS = %w[folders].freeze

      def self.run(args)
        new(args).execute
      end

      def initialize(args)
        @args = args
        @config = Config.new
        @dry_run = ENV["DIFFDASH_DRY_RUN"] == "true" || args.include?("--dry-run")
        @help = args.include?("--help") || args.include?("-h")
        @verbose = args.include?("--verbose") || args.include?("-v")
        @subcommand = extract_subcommand(args)
        @dynamic_metrics = []
      end

      def execute
        # Validate arguments first (unless asking for help)
        unless @help
          invalid_args = find_invalid_arguments
          if invalid_args.any?
            warn "ERROR: Unknown argument(s): #{invalid_args.join(", ")}"
            warn ""
            warn "Run 'diffdash --help' for usage information."
            return 1
          end
        end

        if @help && @subcommand.nil?
          print_help
          return 0
        end

        # Handle subcommands
        case @subcommand
        when "folders"
          return list_grafana_folders
        end

        warn "[diffdash] v#{VERSION}"

        change_set = Engine::ChangeSet.from_git
        log_verbose("Branch: #{change_set.branch_name}")
        log_verbose("Changed files: #{change_set.changed_files.size}")
        log_verbose("Filtered Ruby files: #{change_set.filtered_files.size}")

        engine = Engine::Engine.new(config: @config)
        bundle = engine.run(change_set: change_set)
        @dynamic_metrics = bundle.metadata[:dynamic_metrics] || []
        log_verbose("Total signals extracted: #{bundle.logs.size + bundle.metrics.size}")

        if bundle.empty?
          warn "[diffdash] No observability signals found in changed files"
          warn_dynamic_metrics_summary
          warn "[diffdash] Dashboard not created"
          return 0
        end

        outputs = build_outputs(change_set)
        results, errors = run_outputs(outputs, bundle)

        # Print Grafana JSON if available (preserve existing behavior)
        grafana_result = results[:grafana]
        json_result = results[:json]
        if grafana_result
          puts JSON.pretty_generate(grafana_result[:payload])
        elsif json_result
          puts JSON.pretty_generate(json_result[:payload])
        end

        # Summaries
        print_signal_summary(bundle, url: grafana_result&.dig(:url))

        warn_output_errors(errors) if errors.any?

        errors.size == outputs.size ? 1 : 0
      rescue LimitExceededError => e
        warn "ERROR: #{e.message}"
        1
      rescue GitContextError => e
        warn "ERROR: #{e.message}"
        1
      rescue StandardError => e
        warn "ERROR: #{e.message}"
        warn e.backtrace.first(5).join("\n") if @verbose
        1
      end

      private

      def extract_subcommand(args)
        args.find { |arg| VALID_SUBCOMMANDS.include?(arg) }
      end

      def find_invalid_arguments
        @args.reject do |arg|
          VALID_OPTIONS.include?(arg) || VALID_SUBCOMMANDS.include?(arg)
        end
      end

      def build_outputs(change_set)
        title = Formatters::DashboardTitle.sanitize(change_set.branch_name)

        @config.outputs.map do |output|
          case output
          when :grafana
            Outputs::Grafana.new(
              title: title,
              folder_id: @config.grafana_folder_id,
              dry_run: @dry_run,
              verbose: @verbose
            )
          when :json
            Outputs::Json.new
          when :kibana
            Outputs::Kibana.new
          else
            raise ArgumentError, "Unknown output '#{output}'. Valid outputs: grafana, json, kibana."
          end
        end
      end

      def run_outputs(outputs, bundle)
        results = {}
        errors = []

        outputs.each do |adapter|
          adapter_key = adapter_key(adapter)
          result = { payload: nil, url: nil }

          begin
            payload = adapter.render(bundle)
            result[:payload] = payload

            if adapter.respond_to?(:upload)
              upload_result = adapter.upload(payload)
              result[:url] = upload_result[:url]
            end
          rescue StandardError => e
            errors << { adapter: adapter_key, error: e }
            next
          end

          results[adapter_key] = result
        end

        [results, errors]
      end

      def adapter_key(adapter)
        case adapter
        when Outputs::Grafana then :grafana
        when Outputs::Json then :json
        when Outputs::Kibana then :kibana
        else
          class_name = adapter.class.name
          return :adapter if class_name.nil? || class_name.empty?
          class_name.split("::").last.downcase.to_sym
        end
      end

      def warn_output_errors(errors)
        warn ""
        warn "[diffdash] Some outputs failed:"
        errors.each do |entry|
          warn "  • #{entry[:adapter]}: #{entry[:error].message}"
          warn entry[:error].backtrace.first(3).join("\n") if @verbose
        end
        warn ""
      end

      def list_grafana_folders
        client = Clients::Grafana.new
        folders = client.list_folders

        if folders.empty?
          puts "No folders found (dashboards will be created in General folder)"
        else
          puts "Available Grafana folders:"
          puts ""
          folders.each do |folder|
            puts "  ID: #{folder['id'].to_s.ljust(6)} Title: #{folder['title']}"
          end
          puts ""
          puts "Set DIFFDASH_GRAFANA_FOLDER_ID in your .env file to use a specific folder"
        end
        0
      rescue Clients::Grafana::ConnectionError => e
        warn "ERROR: #{e.message}"
        1
      rescue Error => e
        warn "ERROR: #{e.message}"
        1
      end

      def print_signal_summary(bundle, url: nil)
        log_count = bundle.logs.size
        counter_count = bundle.metrics.count { |s| s.metadata[:metric_type] == :counter }
        gauge_count = bundle.metrics.count { |s| s.metadata[:metric_type] == :gauge }
        histogram_count = bundle.metrics.count { |s| s.metadata[:metric_type] == :histogram }
        summary_count = bundle.metrics.count { |s| s.metadata[:metric_type] == :summary }
        dynamic_count = @dynamic_metrics&.size || 0

        # Build signal breakdown
        signal_parts = []
        signal_parts << pluralize(log_count, "log") if log_count > 0
        signal_parts << pluralize(counter_count, "counter") if counter_count > 0
        signal_parts << pluralize(gauge_count, "gauge") if gauge_count > 0
        signal_parts << pluralize(histogram_count, "histogram") if histogram_count > 0
        signal_parts << pluralize(summary_count, "summary") if summary_count > 0

        # Build panel count
        total_panels = [log_count, counter_count, gauge_count, histogram_count, summary_count].count { |c| c > 0 }

        warn ""
        warn "[diffdash] Dashboard created with #{pluralize(total_panels, "panel")}: #{signal_parts.join(", ")}"

        if url
          warn "[diffdash] Uploaded to: #{url}"
        else
          warn "[diffdash] Mode: dry-run (not uploaded)"
        end

        if dynamic_count > 0
          warn "[diffdash] Note: #{pluralize(dynamic_count, "dynamic metric")} could not be added"
          warn_dynamic_metrics_details if @verbose
        end

        warn ""
      end

      def pluralize(count, word)
        count == 1 ? "#{count} #{word}" : "#{count} #{word}s"
      end

      def warn_dynamic_metrics_summary
        dynamic_count = @dynamic_metrics&.size || 0
        return if dynamic_count == 0

        warn "[diffdash] Note: #{dynamic_count} dynamic metric#{"s" unless dynamic_count == 1} detected but cannot be added to dashboard"
        warn_dynamic_metrics_details if @verbose
      end

      def warn_dynamic_metrics_details
        return if @dynamic_metrics.nil? || @dynamic_metrics.empty?

        warn ""
        warn "[diffdash] ⚠️  Dynamic metrics use runtime values and cannot be added to the dashboard:"

        @dynamic_metrics.each do |m|
          warn "  • #{m[:file]}:#{m[:line]} - #{m[:receiver]}.#{m[:type]} in #{m[:class]}"
        end

        warn ""
        warn "[diffdash] Tip: Use static metric names with labels instead:"
        warn "  Prometheus.counter(:my_metric).increment(labels: { entity_id: id })"
      end

      def log_verbose(message)
        warn "[diffdash] #{message}" if @verbose
      end

      def print_help
        puts <<~HELP
          Usage: diffdash [command] [options]

          Analyzes Ruby files changed in the current PR and generates a Grafana dashboard.

          Commands:
            folders      List available Grafana folders
            (none)       Run analysis and generate/upload dashboard

          Options:
            --dry-run    Generate JSON only, skip Grafana connection
            --verbose    Print detailed progress information
            --help       Show this help message

          Environment Variables (set in .env file):
            DIFFDASH_GRAFANA_URL        Grafana instance URL (required)
            DIFFDASH_GRAFANA_TOKEN      Grafana API token (required)
            DIFFDASH_GRAFANA_FOLDER_ID  Target folder ID (optional)
            DIFFDASH_OUTPUTS            Comma-separated outputs (default: grafana)
            DIFFDASH_DRY_RUN            Set to 'true' to force dry-run mode

          Output:
            Prints output JSON to STDOUT (Grafana first if configured).
            Errors and progress info go to STDERR.

          Example .env file:
            DIFFDASH_GRAFANA_URL=https://myorg.grafana.net
            DIFFDASH_GRAFANA_TOKEN=glsa_xxxxxxxxxxxx
            DIFFDASH_GRAFANA_FOLDER_ID=42
        HELP
      end
    end
  end
end
