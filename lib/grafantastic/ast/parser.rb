# frozen_string_literal: true

require "parser/current"

module Grafantastic
  module AST
    class Parser
      class << self
        def parse(source, file_path = "(source)")
          buffer = ::Parser::Source::Buffer.new(file_path, source: source)
          parser = ::Parser::CurrentRuby.new
          parser.diagnostics.consumer = ->(diagnostic) {} # Silence warnings
          parser.parse(buffer)
        rescue ::Parser::SyntaxError => e
          warn "[grafantastic] Syntax error in #{file_path}: #{e.message}"
          nil
        end
      end
    end
  end
end
