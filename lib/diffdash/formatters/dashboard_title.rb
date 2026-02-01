# frozen_string_literal: true

module Diffdash
  module Formatters
    # Sanitizes branch names into valid Grafana dashboard titles
    # - Removes special characters
    # - Collapses multiple dashes
    # - Truncates to reasonable length
    # - Provides fallback for empty results
    class DashboardTitle
      MAX_LENGTH = 40
      FALLBACK_TITLE = 'pr-dashboard'

      # @param branch_name [String] Git branch name
      # @return [String] Sanitized dashboard title
      def self.sanitize(branch_name)
        sanitized = branch_name
                    .gsub(/[^a-zA-Z0-9\-_]/, '-') # Replace special chars with dash
                    .gsub(/-+/, '-')                # Collapse multiple dashes
                    .gsub(/^-|-$/, '')              # Remove leading/trailing dashes

        sanitized = FALLBACK_TITLE if sanitized.empty?
        sanitized[0, MAX_LENGTH]
      end
    end
  end
end
