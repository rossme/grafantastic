# frozen_string_literal: true

module Diffdash
  # Filters files based on configurable rules.
  #
  # By default, includes only Ruby files and excludes test files and directories.
  # Can be customized via diffdash.yml:
  #
  #   ignore_paths:
  #     - vendor/
  #     - lib/legacy/
  #
  #   include_paths:
  #     - app/
  #     - lib/
  #
  #   excluded_suffixes:
  #     - _spec.rb
  #     - _test.rb
  #
  #   excluded_directories:
  #     - spec
  #     - test
  #     - config
  #
  class FileFilter
    DEFAULT_EXCLUDED_SUFFIXES = %w[_spec.rb _test.rb].freeze
    DEFAULT_EXCLUDED_DIRECTORIES = %w[spec test config].freeze
    RUBY_EXTENSION = '.rb'

    attr_reader :excluded_suffixes, :excluded_directories, :ignore_paths, :include_paths

    # Initialize with optional config for customizable filtering rules.
    #
    # @param config [Config, nil] configuration object with filtering rules
    def initialize(config: nil)
      @excluded_suffixes = config&.excluded_suffixes || DEFAULT_EXCLUDED_SUFFIXES
      @excluded_directories = config&.excluded_directories || DEFAULT_EXCLUDED_DIRECTORIES
      @ignore_paths = config&.ignore_paths || []
      @include_paths = config&.include_paths || []
      @excluded_directories_regex = build_directories_regex(@excluded_directories)
    end

    def filter(files)
      files.select { |f| include_file?(f) }
    end

    def include_file?(file_path)
      return false unless file_path.end_with?(RUBY_EXTENSION)
      return false if excluded_suffix?(file_path)
      return false if excluded_directory?(file_path)
      return false if ignored_path?(file_path)
      return false if include_paths_configured? && !included_path?(file_path)

      true
    end

    # Class-level convenience method.
    # Uses default filtering rules (no config).
    def self.filter(files)
      new.filter(files)
    end

    # Class-level convenience method.
    # Uses default filtering rules (no config).
    def self.include_file?(file_path)
      new.include_file?(file_path)
    end

    private

    def excluded_suffix?(file_path)
      @excluded_suffixes.any? { |suffix| file_path.end_with?(suffix) }
    end

    def excluded_directory?(file_path)
      file_path.match?(@excluded_directories_regex)
    end

    def ignored_path?(file_path)
      @ignore_paths.any? do |pattern|
        match_path_pattern?(file_path, pattern)
      end
    end

    def included_path?(file_path)
      @include_paths.any? do |pattern|
        match_path_pattern?(file_path, pattern)
      end
    end

    def include_paths_configured?
      @include_paths.any?
    end

    def match_path_pattern?(file_path, pattern)
      # Support glob-style patterns and simple prefix matching
      if pattern.include?('*')
        File.fnmatch?(pattern, file_path, File::FNM_PATHNAME)
      else
        # Normalize pattern to ensure consistent matching
        normalized = pattern.chomp('/')
        file_path.start_with?(normalized) || file_path.include?("/#{normalized}/")
      end
    end

    def build_directories_regex(directories)
      return /(?!)/ if directories.empty? # Never match

      escaped = directories.map { |d| Regexp.escape(d) }
      Regexp.new("/(#{escaped.join('|')})/")
    end
  end
end
