# frozen_string_literal: true

require 'parser/current'

module Diffdash
  module AST
    # Parses Ruby source code into an Abstract Syntax Tree (AST).
    #
    # Wraps the `parser` gem to provide a simple interface for parsing Ruby files.
    # Handles syntax errors gracefully by returning nil and logging a warning.
    #
    # @example
    #   ast = Parser.parse(File.read("app/models/user.rb"), "app/models/user.rb")
    class Parser
      class << self
        def parse(source, file_path = '(source)')
          buffer = ::Parser::Source::Buffer.new(file_path, source: source)
          parser = ::Parser::CurrentRuby.new
          parser.diagnostics.consumer = ->(diagnostic) {} # Silence warnings
          parser.parse(buffer)
        rescue ::Parser::SyntaxError => e
          warn "[diffdash] Syntax error in #{file_path}: #{e.message}"
          nil
        end
      end
    end
  end
end
