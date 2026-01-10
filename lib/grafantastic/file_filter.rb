# frozen_string_literal: true

module Grafantastic
  class FileFilter
    EXCLUDED_SUFFIXES = %w[_spec.rb _test.rb].freeze
    EXCLUDED_DIRECTORIES = %r{/(spec|test|config)/}.freeze
    RUBY_EXTENSION = ".rb"

    class << self
      def filter(files)
        files.select { |f| include_file?(f) }
      end

      def include_file?(file_path)
        return false unless file_path.end_with?(RUBY_EXTENSION)
        return false if excluded_suffix?(file_path)
        return false if excluded_directory?(file_path)

        true
      end

      private

      def excluded_suffix?(file_path)
        EXCLUDED_SUFFIXES.any? { |suffix| file_path.end_with?(suffix) }
      end

      def excluded_directory?(file_path)
        file_path.match?(EXCLUDED_DIRECTORIES)
      end
    end
  end
end
