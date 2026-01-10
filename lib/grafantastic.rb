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
require_relative "grafantastic/configuration"
require_relative "grafantastic/git_context"
require_relative "grafantastic/file_filter"
require_relative "grafantastic/signals/signal"
require_relative "grafantastic/ast/parser"
require_relative "grafantastic/ast/visitor"
require_relative "grafantastic/ast/inheritance_resolver"
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
    def self.run(args)
      new(args).execute
    end

    def initialize(args)
      @args = args
      @config = Config.new
      @configuration = Configuration.new
      @dry_run = ENV["GRAFANTASTIC_DRY_RUN"] == "true" || args.include?("--dry-run")
      @help = args.include?("--help") || args.include?("-h")
      @verbose = args.include?("--verbose") || args.include?("-v")
      @subcommand = extract_subcommand(args)
    end

    def execute
      if @help && @subcommand.nil?
        print_help
        return 0
      end

      # Handle subcommands
      case @subcommand
      when "config"
        return execute_config
      end

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

      # Print summary of what will be created
      print_signal_summary(all_signals)

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

      # Output or upload
      if @dry_run
        puts JSON.pretty_generate(dashboard_json)
      else
        result = @grafana_client.upload(dashboard_json)
        warn "Dashboard uploaded: #{result[:url]}" if result[:url]
        puts JSON.pretty_generate(dashboard_json)
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
      subcommands = %w[config]
      args.find { |arg| subcommands.include?(arg) }
    end

    def execute_config
      config_args = @args.dup
      config_args.delete("config")

      if @help || config_args.empty?
        print_config_help
        return 0
      end

      action = config_args.shift

      case action
      when "set"
        key, value = config_args.shift(2)
        global = config_args.include?("--global")

        unless key && value
          warn "ERROR: Usage: grafantastic config set <key> <value> [--global]"
          return 1
        end

        @configuration.save(key, value, global: global)
        scope = global ? "global" : "local"
        warn "Set #{key} in #{scope} config"
        0

      when "get"
        key = config_args.shift
        unless key
          warn "ERROR: Usage: grafantastic config get <key>"
          return 1
        end

        value = @configuration.send(key) rescue nil
        if value
          puts key == "grafana_token" ? "[REDACTED]" : value
        else
          warn "#{key} is not set"
        end
        0

      when "list"
        puts YAML.dump(@configuration.show)
        0

      when "delete"
        key = config_args.shift
        global = config_args.include?("--global")

        unless key
          warn "ERROR: Usage: grafantastic config delete <key> [--global]"
          return 1
        end

        @configuration.delete(key, global: global)
        scope = global ? "global" : "local"
        warn "Deleted #{key} from #{scope} config"
        0

      when "folders"
        list_grafana_folders

      else
        warn "ERROR: Unknown config action: #{action}"
        print_config_help
        1
      end
    rescue ArgumentError => e
      warn "ERROR: #{e.message}"
      1
    end

    def list_grafana_folders
      unless @configuration.configured?
        warn "ERROR: Grafana not configured. Run: grafantastic config set grafana_url <url>"
        return 1
      end

      client = GrafanaClient.new(
        url: @configuration.grafana_url,
        token: @configuration.grafana_token
      )
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
        puts "Use: grafantastic config set grafana_folder_id <ID>"
      end
      0
    rescue GrafanaClient::ConnectionError => e
      warn "ERROR: #{e.message}"
      1
    end

    def validate_grafana_connection!
      log_verbose("Validating Grafana connection...")

      unless @configuration.configured?
        raise Error, "Grafana not configured. Run: grafantastic config set grafana_url <url> --global"
      end

      client = GrafanaClient.new(
        url: @configuration.grafana_url,
        token: @configuration.grafana_token
      )
      client.health_check!

      log_verbose("Connected to Grafana at #{client.url}")
      @grafana_client = client
    end

    def extract_signals(files)
      signals = []
      @dynamic_metrics = []
      inheritance_resolver = AST::InheritanceResolver.new

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

        # Resolve parent classes and extract their signals (depth = 1)
        visitor.class_definitions.each do |class_def|
          parent_file = inheritance_resolver.resolve_parent(class_def[:parent], file_path)
          next unless parent_file && File.exist?(parent_file)

          parent_source = File.read(parent_file)
          parent_ast = AST::Parser.parse(parent_source, parent_file)
          next unless parent_ast

          parent_visitor = AST::Visitor.new(file_path: parent_file, inheritance_depth: 1)
          parent_visitor.process(parent_ast)

          signals.concat(Signals::LogExtractor.extract(parent_visitor))
          signals.concat(Signals::MetricExtractor.extract(parent_visitor))
          collect_dynamic_metrics(parent_visitor, parent_file)
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

    def print_signal_summary(signals)
      log_counts = signals.count { |s| s.type == :log }
      metric_counts = signals.count { |s| %i[counter gauge histogram].include?(s.type) }
      dynamic_count = @dynamic_metrics&.size || 0

      # Build panel count description
      parts = []
      parts << "#{log_counts} log panel#{"s" unless log_counts == 1}" if log_counts > 0
      parts << "#{metric_counts} metric panel#{"s" unless metric_counts == 1}" if metric_counts > 0

      if parts.empty?
        warn "[grafantastic] Creating dashboard with default info panel (no signals found)"
      else
        warn "[grafantastic] Creating dashboard with #{parts.join(", ")}"
      end

      if dynamic_count > 0
        warn "[grafantastic] Please see: #{dynamic_count} dynamic metric#{"s" unless dynamic_count == 1} could not be added"
        warn_dynamic_metrics_details if @verbose
      end

      warn ""
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
          config       Configure Grafana connection settings
          (none)       Run analysis and generate/upload dashboard

        Options:
          --dry-run    Generate JSON only, skip Grafana connection
          --verbose    Print detailed progress information
          --help       Show this help message

        Environment Variables (override config file):
          GRAFANA_URL          Grafana instance URL
          GRAFANA_TOKEN        Grafana API token
          GRAFANA_FOLDER_ID    Target folder ID
          GRAFANTASTIC_DRY_RUN Set to 'true' to force dry-run mode

        Configuration:
          Settings are loaded from ~/.grafantastic.yml (global) and
          .grafantastic.yml (local, in current directory).

          Run 'grafantastic config --help' for configuration commands.

        Output:
          Prints valid Grafana dashboard JSON to STDOUT.
          Errors and progress info go to STDERR.
      HELP
    end

    def print_config_help
      puts <<~HELP
        Usage: grafantastic config <action> [options]

        Configure Grafana connection settings.

        Actions:
          set <key> <value>    Set a config value
          get <key>            Get a config value
          list                 Show all config values
          delete <key>         Delete a config value
          folders              List available Grafana folders

        Options:
          --global             Apply to ~/.grafantastic.yml (default: local)
          --help               Show this help message

        Available Keys:
          grafana_url          Grafana instance URL (e.g., https://myorg.grafana.net)
          grafana_token        Grafana API token (Service Account token)
          grafana_folder_id    Target folder ID for dashboards
          grafana_folder_name  Target folder name (for display)

        Examples:
          grafantastic config set grafana_url https://myorg.grafana.net --global
          grafantastic config set grafana_token glsa_xxx --global
          grafantastic config folders
          grafantastic config set grafana_folder_id 42
          grafantastic config list
      HELP
    end
  end
end
