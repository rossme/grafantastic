# frozen_string_literal: true

module Diffdash
  module Linter
    # Base class for all lint rules.
    # Each rule analyzes AST nodes and reports issues.
    #
    # Subclasses must implement:
    #   - #rule_name (String)
    #   - #check(log_call, source_file) -> Issue or nil
    #
    class Base
      Issue = Struct.new(:rule, :file, :line, :message, :suggestion, :context, keyword_init: true)

      def rule_name
        raise NotImplementedError, "#{self.class} must implement #rule_name"
      end

      def description
        raise NotImplementedError, "#{self.class} must implement #description"
      end

      # Check a single log call for issues
      # @param log_call [Hash] Log call data from visitor
      # @param source_file [String] Path to source file
      # @return [Issue, nil] Issue if found, nil otherwise
      def check(log_call, source_file)
        raise NotImplementedError, "#{self.class} must implement #check"
      end
    end
  end
end
