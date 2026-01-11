# frozen_string_literal: true

require "json"
require "digest"

begin
  require "dotenv/load"
rescue LoadError
  # dotenv is optional
end

require_relative "grafantastic/version"
require_relative "grafantastic/config"
require_relative "grafantastic/git_context"
require_relative "grafantastic/file_filter"
require_relative "grafantastic/signals/signal"
require_relative "grafantastic/ast/parser"
require_relative "grafantastic/ast/visitor"
require_relative "grafantastic/ast/ancestor_resolver"
require_relative "grafantastic/signals/log_extractor"
require_relative "grafantastic/signals/metric_extractor"
require_relative "grafantastic/validation/limits"
require_relative "grafantastic/dashboard/panel_templates"
require_relative "grafantastic/dashboard/builder"
require_relative "grafantastic/grafana_client"

module Grafantastic
  class Error < StandardError; end
  class LimitExceededError < Error; end
  class GitContextError < Error; end

  class CLI
    VALID_OPTIONS = %w[--dry-run --verbose -v --help -h].freeze
    VALID_SUBCOMMANDS = %w[folders].freeze

    def self.run(args)
      new(args).execute
    end

    def initialize(args)
      @args = args
      @config = Config.new
      @dry_run = ENV["GRAFANTASTIC_DRY_RUN"] == "true" || args.include?("--dry-run")
      @help = args.include?("--help") || args.include?("-h")
      @verbose = args.include?("--verbose") || args.include?("-v")
      @subcommand = extract_subcommand(args)
    end

    def execute
      # Validate arguments first (unless asking for help)
      unless @help
        invalid_args = find_invalid_arguments
        if invalid_args.any?
          warn "ERROR: Unknown argument(s): #{invalid_args.join(", ")}"
          warn ""
          warn "Run 'grafantastic --help' for usage information."
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

      warn "[grafantastic] v#{VERSION}"

      # Validate Grafana connection upfront (unless dry-run)
      unless @dry_run
        validate_grafana_connection!
      end

      git_context = GitContext.new
      changed_files = git_context.changed_files
      branch_name = git_context.branch_name

      log_verbose("Branch: #{branch_name}")
      log_verbose("Changed files: #{changed_files.size}")

      filtered_files = FileFilter.filter(changed_files)
      log_verbose("Filtered Ruby files: #{filtered_files.size}")

      if filtered_files.empty?
        log_verbose("No Ruby application files changed")
      end

      # Extract signals from all filtered files
      all_signals = extract_signals(filtered_files)
      log_verbose("Total signals extracted: #{all_signals.size}")

      # Exit early if no signals found
      if all_signals.empty?
        warn "[grafantastic] No observability signals found in changed files"
        warn_dynamic_metrics_summary
        warn "[grafantastic] Dashboard not created"
        return 0
      end

      # Validate against guard rails
      validator = Validation::Limits.new(@config)
      validator.validate!(all_signals)

      # Build dashboard
      dashboard_title = sanitize_dashboard_title(branch_name)
      builder = Dashboard::Builder.new(
        title: dashboard_title,
        signals: all_signals,
        config: @config
      )
      dashboard_json = builder.build

      # Output JSON first
      puts JSON.pretty_generate(dashboard_json)

      # Then print summary after the JSON
      if @dry_run
        print_signal_summary(all_signals, url: nil)
      else
        result = @grafana_client.upload(dashboard_json)
        print_signal_summary(all_signals, url: result[:url])
      end

      0
    rescue LimitExceededError => e
      warn "ERROR: #{e.message}"
      1
    rescue GitContextError => e
      warn "ERROR: #{e.message}"
      1
    rescue GrafanaClient::ConnectionError => e
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

    def list_grafana_folders
      client = GrafanaClient.new
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
        puts "Set GRAFANA_FOLDER_ID in your .env file to use a specific folder"
      end
      0
    rescue GrafanaClient::ConnectionError => e
      warn "ERROR: #{e.message}"
      1
    rescue Error => e
      warn "ERROR: #{e.message}"
      1
    end

    def validate_grafana_connection!
      log_verbose("Validating Grafana connection...")

      client = GrafanaClient.new
      client.health_check!

      log_verbose("Connected to Grafana at #{client.url}")
      @grafana_client = client
    end

    def extract_signals(files)
      signals = []
      @dynamic_metrics = []
      ancestor_resolver = AST::AncestorResolver.new

      files.each do |file_path|
        next unless File.exist?(file_path)

        source = File.read(file_path)
        ast = AST::Parser.parse(source, file_path)
        next unless ast

        # Extract from the file directly (depth = 0)
        visitor = AST::Visitor.new(file_path: file_path, inheritance_depth: 0)
        visitor.process(ast)

        signals.concat(Signals::LogExtractor.extract(visitor))
        signals.concat(Signals::MetricExtractor.extract(visitor))
        collect_dynamic_metrics(visitor, file_path)

        # Collect all ancestors (parents + included modules, recursively)
        ancestors = ancestor_resolver.collect_ancestors(visitor, file_path)

        ancestors.each do |ancestor|
          ancestor_source = File.read(ancestor[:file])
          ancestor_ast = AST::Parser.parse(ancestor_source, ancestor[:file])
          next unless ancestor_ast

          ancestor_visitor = AST::Visitor.new(
            file_path: ancestor[:file],
            inheritance_depth: ancestor[:depth]
          )
          ancestor_visitor.process(ancestor_ast)

          signals.concat(Signals::LogExtractor.extract(ancestor_visitor))
          signals.concat(Signals::MetricExtractor.extract(ancestor_visitor))
          collect_dynamic_metrics(ancestor_visitor, ancestor[:file])
        end
      end

      signals.uniq { |s| [s.type, s.name, s.source_file, s.defining_class] }
    end

    def collect_dynamic_metrics(visitor, file_path)
      visitor.dynamic_metric_calls.each do |call|
        @dynamic_metrics << {
          file: file_path,
          line: call[:line],
          type: call[:metric_type],
          class: call[:defining_class],
          receiver: call[:receiver]
        }
      end
    end

    def print_signal_summary(signals, url: nil)
      log_count = signals.count { |s| s.type == :log }
      counter_count = signals.count { |s| s.type == :metric && s.metadata[:metric_type] == :counter }
      gauge_count = signals.count { |s| s.type == :metric && s.metadata[:metric_type] == :gauge }
      histogram_count = signals.count { |s| s.type == :metric && s.metadata[:metric_type] == :histogram }
      summary_count = signals.count { |s| s.type == :metric && s.metadata[:metric_type] == :summary }
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
      warn "[grafantastic] Dashboard created with #{pluralize(total_panels, "panel")}: #{signal_parts.join(", ")}"

      if url
        warn "[grafantastic] Uploaded to: #{url}"
      else
        warn "[grafantastic] Mode: dry-run (not uploaded)"
      end

      if dynamic_count > 0
        warn "[grafantastic] Note: #{pluralize(dynamic_count, "dynamic metric")} could not be added"
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

      warn "[grafantastic] Note: #{dynamic_count} dynamic metric#{"s" unless dynamic_count == 1} detected but cannot be added to dashboard"
      warn_dynamic_metrics_details if @verbose
    end

    def warn_dynamic_metrics_details
      return if @dynamic_metrics.nil? || @dynamic_metrics.empty?

      warn ""
      warn "[grafantastic] ⚠️  Dynamic metrics use runtime values and cannot be added to the dashboard:"

      @dynamic_metrics.each do |m|
        warn "  • #{m[:file]}:#{m[:line]} - #{m[:receiver]}.#{m[:type]} in #{m[:class]}"
      end

      warn ""
      warn "[grafantastic] Tip: Use static metric names with labels instead:"
      warn "  Prometheus.counter(:my_metric).increment(labels: { entity_id: id })"
    end

    def sanitize_dashboard_title(branch_name)
      sanitized = branch_name
        .gsub(/[^a-zA-Z0-9\-_]/, "-")
        .gsub(/-+/, "-")
        .gsub(/^-|-$/, "")

      sanitized = "pr-dashboard" if sanitized.empty?
      sanitized[0, 40]
    end

    def log_verbose(message)
      warn "[grafantastic] #{message}" if @verbose
    end

    def print_help
      puts <<~HELP
        Usage: grafantastic [command] [options]

        Analyzes Ruby files changed in the current PR and generates a Grafana dashboard.

        Commands:
          folders      List available Grafana folders
          (none)       Run analysis and generate/upload dashboard

        Options:
          --dry-run    Generate JSON only, skip Grafana connection
          --verbose    Print detailed progress information
          --help       Show this help message

        Environment Variables (set in .env file):
          GRAFANA_URL          Grafana instance URL (required)
          GRAFANA_TOKEN        Grafana API token (required)
          GRAFANA_FOLDER_ID    Target folder ID (optional)
          GRAFANTASTIC_DRY_RUN Set to 'true' to force dry-run mode

        Output:
          Prints valid Grafana dashboard JSON to STDOUT.
          Errors and progress info go to STDERR.

        Example .env file:
          GRAFANA_URL=https://myorg.grafana.net
          GRAFANA_TOKEN=glsa_xxxxxxxxxxxx
          GRAFANA_FOLDER_ID=42
      HELP
    end
  end
end
