# frozen_string_literal: true

module Diffdash
  module CLI
    # Thin CLI glue. Orchestrates engine + output adapters.
    class Runner
      VALID_OPTIONS = %w[--dry-run --verbose -v --help -h --version --config --list-signals].freeze
      VALID_SUBCOMMANDS = %w[folders rspec].freeze
      OUTPUT_SUBCOMMANDS = %w[grafana datadog kibana json].freeze

      def self.run(args)
        new(args).execute
      end

      def initialize(args)
        @args = args
        @config_path = extract_config_path(args)
        @config = Config.new(config_path: @config_path)
        @dry_run = ENV['DIFFDASH_DRY_RUN'] == 'true' || args.include?('--dry-run')
        @help = args.include?('--help') || args.include?('-h')
        @version = args.include?('--version')
        @verbose = args.include?('--verbose') || args.include?('-v')
        @list_signals = args.include?('--list-signals')
        @subcommand = extract_subcommand(args)
        @output_subcommand = extract_output_subcommand(args)
        @dynamic_metrics = []
      end

      def execute
        # Handle version and help early (skip validation for these)
        if @version
          puts "diffdash #{VERSION}"
          return 0
        end

        if @help && @subcommand.nil?
          print_help
          return 0
        end

        # Validate arguments (after version/help checks)
        invalid_args = find_invalid_arguments
        if invalid_args.any?
          warn "ERROR: Unknown argument(s): #{invalid_args.join(', ')}"
          warn ''
          warn "Run 'diffdash --help' for usage information."
          return 1
        end

        # Handle subcommands
        case @subcommand
        when 'folders'
          return list_grafana_folders
        when 'rspec'
          return run_rspec
        end

        warn "[diffdash] v#{VERSION}"
        log_config_info

        change_set = Engine::ChangeSet.from_git(config: @config)
        log_verbose("Branch: #{change_set.branch_name}")
        log_verbose("Changed files: #{change_set.changed_files.size}")
        log_verbose("Filtered Ruby files: #{change_set.filtered_files.size}")

        # Early exit if no files to analyze
        if change_set.filtered_files.empty?
          warn '[diffdash] No changed files found'
          warn '[diffdash] Dashboard not created'
          return 0
        end

        engine = Engine::Engine.new(config: @config)
        bundle = engine.run(change_set: change_set)
        @dynamic_metrics = bundle.metadata[:dynamic_metrics] || []
        @limit_warnings = bundle.metadata[:limit_warnings] || []
        log_verbose("Total signals extracted: #{bundle.logs.size + bundle.metrics.size}")

        # Handle --list-signals flag
        if @list_signals
          print_signals_list(bundle)
          return 0
        end

        if bundle.empty?
          warn '[diffdash] No observability signals found in changed files'
          warn_dynamic_metrics_summary
          warn '[diffdash] Dashboard not created'
          return 0
        end

        outputs = build_outputs(change_set)
        results, errors = run_outputs(outputs, bundle)

        # Print JSON output if available
        grafana_result = results[:grafana]
        json_result = results[:json]
        if grafana_result
          puts JSON.pretty_generate(grafana_result[:payload])
        elsif json_result
          puts JSON.pretty_generate(json_result[:payload])
        end

        # Find dashboard URL from any successful output
        dashboard_url = find_dashboard_url(results)
        any_failed = errors.any?
        
        # Summaries
        print_signal_summary(bundle, url: dashboard_url, upload_failed: any_failed)

        # Post PR comment with dashboard link and signal summary
        post_pr_comment(dashboard_url, bundle) if dashboard_url && @config.pr_comment?

        warn_limit_warnings if @limit_warnings.any?
        warn_output_errors(errors) if errors.any?

        errors.size == outputs.size ? 1 : 0
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

      def extract_output_subcommand(args)
        args.find { |arg| OUTPUT_SUBCOMMANDS.include?(arg) }
      end

      def extract_config_path(args)
        idx = args.index('--config')
        return nil unless idx

        args[idx + 1]
      end

      def find_invalid_arguments
        skip_next = false
        @args.reject do |arg|
          if skip_next
            skip_next = false
            next true # Skip the value for --config
          end

          if arg == '--config'
            skip_next = true
            next true
          end

          VALID_OPTIONS.include?(arg) || VALID_SUBCOMMANDS.include?(arg) || OUTPUT_SUBCOMMANDS.include?(arg)
        end
      end

      def log_config_info
        return unless @verbose

        if @config.loaded_from
          log_verbose("Config loaded from: #{@config.loaded_from}")
        else
          log_verbose('No config file found, using environment variables and defaults')
        end
      end

      def rspec_args
        idx = @args.index('rspec')
        return [] unless idx

        @args[(idx + 1)..] || []
      end

      def build_outputs(change_set)
        title = Formatters::DashboardTitle.sanitize(change_set.branch_name)

        # If output subcommand specified (e.g., `diffdash kibana`), use only that output
        outputs_to_use = if @output_subcommand
                           [@output_subcommand.to_sym]
                         else
                           @config.outputs
                         end

        outputs_to_use.map do |output|
          case output
          when :grafana
            Outputs::Grafana.new(
              title: title,
              folder_id: @config.grafana_folder_id,
              dry_run: @dry_run,
              verbose: @verbose,
              default_env: @config.default_env,
              app_name: @config.app_name,
              pr_deploy_annotation_expr: @config.pr_deploy_annotation_expr
            )
          when :datadog
            Outputs::Datadog.new(
              title: title,
              dry_run: @dry_run,
              verbose: @verbose
            )
          when :kibana
            Outputs::Kibana.new(
              title: title,
              dry_run: @dry_run,
              verbose: @verbose
            )
          when :json
            Outputs::Json.new
          else
            raise ArgumentError, "Unknown output '#{output}'. Valid outputs: grafana, datadog, kibana, json."
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
        when Outputs::Kibana then :kibana
        when Outputs::Datadog then :datadog
        when Outputs::Json then :json
        else
          class_name = adapter.class.name
          return :adapter if class_name.nil? || class_name.empty?

          class_name.split('::').last.downcase.to_sym
        end
      end

      def warn_limit_warnings
        warn ''
        warn '[diffdash] ⚠️  Some signals were excluded:'
        @limit_warnings.each do |warning|
          warn "  • #{warning}"
        end
        warn ''
      end

      def warn_output_errors(errors)
        warn ''
        warn '[diffdash] Some outputs failed:'
        errors.each do |entry|
          warn "  • #{entry[:adapter]}: #{entry[:error].message}"
          warn entry[:error].backtrace.first(3).join("\n") if @verbose
        end
        warn ''
      end

      def list_grafana_folders
        client = Clients::Grafana.new
        folders = client.list_folders

        if folders.empty?
          puts 'No folders found (dashboards will be created in General folder)'
        else
          puts 'Available Grafana folders:'
          puts ''
          folders.each do |folder|
            puts "  ID: #{folder['id'].to_s.ljust(6)} Title: #{folder['title']}"
          end
          puts ''
          puts 'Set DIFFDASH_GRAFANA_FOLDER_ID in your .env file to use a specific folder'
        end
        0
      rescue Clients::Grafana::ConnectionError => e
        warn "ERROR: #{e.message}"
        1
      rescue Error => e
        warn "ERROR: #{e.message}"
        1
      end

      def run_rspec
        cmd = ['bundle', 'exec', 'rspec', *rspec_args]
        warn "[diffdash] Running: #{cmd.join(' ')}"
        system(*cmd)
        $?.success? ? 0 : 1
      end

      def find_dashboard_url(results)
        # Check each adapter for a URL, prioritize in order: grafana, kibana, datadog
        [:grafana, :kibana, :datadog].each do |adapter|
          url = results.dig(adapter, :url)
          return url if url
        end
        nil
      end

      def print_signal_summary(bundle, url: nil, upload_failed: false)
        log_count = bundle.logs.size
        counter_count = bundle.metrics.count { |s| s.metadata[:metric_type] == :counter }
        gauge_count = bundle.metrics.count { |s| s.metadata[:metric_type] == :gauge }
        histogram_count = bundle.metrics.count { |s| s.metadata[:metric_type] == :histogram }
        summary_count = bundle.metrics.count { |s| s.metadata[:metric_type] == :summary }
        dynamic_count = @dynamic_metrics&.size || 0

        # Build signal breakdown
        signal_parts = []
        signal_parts << pluralize(log_count, 'log') if log_count > 0
        signal_parts << pluralize(counter_count, 'counter') if counter_count > 0
        signal_parts << pluralize(gauge_count, 'gauge') if gauge_count > 0
        signal_parts << pluralize(histogram_count, 'histogram') if histogram_count > 0
        signal_parts << pluralize(summary_count, 'summary') if summary_count > 0

        # Build panel count
        total_panels = [log_count, counter_count, gauge_count, histogram_count, summary_count].count { |c| c > 0 }

        warn ''
        warn "[diffdash] Dashboard created with #{pluralize(total_panels, 'panel')}: #{signal_parts.join(', ')}"

        if url
          warn "[diffdash] Uploaded to: #{url}"
        elsif upload_failed
          warn '[diffdash] Upload failed (see errors below)'
        elsif @dry_run
          warn '[diffdash] Mode: dry-run (not uploaded)'
        else
          warn '[diffdash] Dashboard JSON printed to stdout'
        end

        if dynamic_count > 0
          warn "[diffdash] Note: #{pluralize(dynamic_count, 'dynamic metric')} could not be added"
          warn_dynamic_metrics_details if @verbose
        end

        warn ''
      end

      def pluralize(count, word)
        count == 1 ? "#{count} #{word}" : "#{count} #{word}s"
      end

      def warn_dynamic_metrics_summary
        dynamic_count = @dynamic_metrics&.size || 0
        return if dynamic_count == 0

        warn "[diffdash] Note: #{dynamic_count} dynamic metric#{unless dynamic_count == 1
                                                                  's'
                                                                end} detected but cannot be added to dashboard"
        warn_dynamic_metrics_details if @verbose
      end

      def warn_dynamic_metrics_details
        return if @dynamic_metrics.nil? || @dynamic_metrics.empty?

        warn ''
        warn '[diffdash] ⚠️  Dynamic metrics use runtime values and cannot be added to the dashboard:'

        @dynamic_metrics.each do |m|
          warn "  • #{m[:file]}:#{m[:line]} - #{m[:receiver]}.#{m[:type]} in #{m[:class]}"
        end

        warn ''
        warn '[diffdash] Tip: Use static metric names with labels instead:'
        warn '  Prometheus.counter(:my_metric).increment(labels: { entity_id: id })'
      end

      def log_verbose(message)
        warn "[diffdash] #{message}" if @verbose
      end

      def print_signals_list(bundle)
        logs = bundle.logs || []
        metrics = bundle.metrics || []

        puts "\n📊 Detected Signals\n\n"

        if logs.any?
          puts "Logs (#{logs.size}):"
          logs_by_class = logs.group_by(&:defining_class)
          logs_by_class.each do |klass, class_logs|
            puts "  #{klass}:"
            class_logs.each do |log|
              level = log.metadata[:level] || "info"
              puts "    • \"#{log.name}\" (#{level})"
            end
          end
          puts ""
        end

        if metrics.any?
          puts "Metrics (#{metrics.size}):"
          metrics_by_type = metrics.group_by { |m| m.metadata[:metric_type] || :counter }
          metrics_by_type.each do |type, type_metrics|
            puts "  #{type.to_s.capitalize}s (#{type_metrics.size}):"
            type_metrics.each do |metric|
              puts "    • #{metric.name}"
            end
          end
          puts ""
        end

        if @dynamic_metrics.any?
          puts "⚠️  Dynamic Metrics (#{@dynamic_metrics.size}) - Cannot be added to dashboard:"
          @dynamic_metrics.each do |m|
            puts "  • #{m[:receiver]}.#{m[:type]} in #{m[:class]} (#{m[:file]}:#{m[:line]})"
          end
          puts ""
        end

        if logs.empty? && metrics.empty?
          puts "No observability signals found in changed files.\n\n"
        end
      end

      def post_pr_comment(dashboard_url, signal_bundle)
        commenter = Services::PrCommenter.new(verbose: @verbose, default_env: @config.default_env)
        return unless commenter.post(dashboard_url: dashboard_url, signal_bundle: signal_bundle)

        log_verbose('Posted dashboard link to PR')
      end

      def print_help
        puts <<~HELP
          Usage: diffdash [output] [options]

          Analyzes Ruby files changed in the current PR and generates observability dashboards.

          Outputs (pick one):
            grafana      Generate and upload Grafana dashboard
            datadog      Generate and upload Datadog dashboard
            kibana       Generate and upload Kibana dashboard
            json         Output raw signal data as JSON
            (none)       Use outputs from config or DIFFDASH_OUTPUTS env var

          Commands:
            folders      List available Grafana folders
            rspec [args] Run the RSpec suite (passes args through)

          Options:
            --config FILE    Path to diffdash.yml configuration file
            --dry-run        Generate JSON only, don't upload
            --list-signals   Show detected signals without generating dashboard
            --verbose        Print detailed progress information
            --version        Show version number
            --help           Show this help message

          Examples:
            diffdash grafana              # Generate Grafana dashboard
            diffdash kibana --verbose     # Generate Kibana dashboard with details
            diffdash datadog --dry-run    # Generate Datadog JSON without uploading
            diffdash --list-signals       # Show what would be detected

          Configuration File (diffdash.yml):
            Create diffdash.yml in your repository root:

            grafana:
              url: https://myorg.grafana.net
              folder_id: 42

            kibana:
              url: https://my-deployment.kb.elastic.cloud
              index_pattern: logs-myapp-default

            datadog:
              site: datadoghq.com

            outputs:
              - grafana    # Default outputs when no subcommand given

          Environment Variables:
            DIFFDASH_GRAFANA_URL        Grafana instance URL
            DIFFDASH_GRAFANA_TOKEN      Grafana API token
            DIFFDASH_KIBANA_URL         Kibana instance URL
            DIFFDASH_KIBANA_API_KEY     Kibana API key
            DIFFDASH_DATADOG_API_KEY    Datadog API key
            DIFFDASH_DATADOG_APP_KEY    Datadog Application key
            DIFFDASH_OUTPUTS            Default outputs (comma-separated)
        HELP
      end
    end
  end
end
