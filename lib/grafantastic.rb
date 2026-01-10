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
      @dry_run = ENV["GRAFANTASTIC_DRY_RUN"] == "true" || args.include?("--dry-run")
      @help = args.include?("--help") || args.include?("-h")
      @verbose = args.include?("--verbose") || args.include?("-v")
    end

    def execute
      if @help
        print_help
        return 0
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

    def validate_grafana_connection!
      log_verbose("Validating Grafana connection...")

      client = GrafanaClient.new
      client.health_check!

      log_verbose("Connected to Grafana at #{client.url}")
      @grafana_client = client
    end

    def extract_signals(files)
      signals = []
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
        end
      end

      signals.uniq { |s| [s.type, s.name, s.source_file, s.defining_class] }
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
        Usage: grafantastic [options]

        Analyzes Ruby files changed in the current PR and generates a Grafana dashboard.

        Options:
          --dry-run    Generate JSON only, skip Grafana connection (no env vars required)
          --verbose    Print detailed progress information
          --help       Show this help message

        Environment Variables:
          GRAFANA_URL          Grafana instance URL (required unless --dry-run)
          GRAFANA_TOKEN        Grafana API token (required unless --dry-run)
          GRAFANA_FOLDER_ID    Target folder ID (optional)
          GRAFANTASTIC_DRY_RUN   Set to 'true' to force dry-run mode

        The CLI validates Grafana connectivity at startup before processing files.
        Use --dry-run to generate dashboard JSON without a Grafana connection.

        Output:
          Prints valid Grafana dashboard JSON to STDOUT.
          Errors and progress info go to STDERR.
      HELP
    end
  end
end
