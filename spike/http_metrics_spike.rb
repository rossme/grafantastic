#!/usr/bin/env ruby
# frozen_string_literal: true

# SPIKE: HTTP Metrics Detection for Diffdash
# 
# Question: Can we detect route/controller classes from changed files
# and generate Prometheus queries for HTTP traffic?
#
# Run: ruby spike/http_metrics_spike.rb

require "parser/current"

module Spike
  # Simulated config
  HTTP_METRICS_CONFIG = {
    enabled: true,
    detect: [
      { namespace: "Routes::" },
      { suffix: "Controller" },
      { namespace: "API::" }
    ],
    rate_metric: "service:http_request_rate:rate$__interval",
    handler_label: "handler",
    labels: { context: "$env" }
  }.freeze

  # Simple class detector
  class ClassDetector
    def initialize(config)
      @config = config
    end

    def detect(source)
      ast = Parser::CurrentRuby.parse(source)
      classes = extract_classes(ast)
      
      classes.select { |c| matches_pattern?(c) }
    end

    private

    def extract_classes(node, namespace = [])
      return [] unless node.is_a?(Parser::AST::Node)

      results = []

      case node.type
      when :module
        name = extract_const_name(node.children[0])
        results += extract_classes(node.children[1], namespace + [name])
      when :class
        name = extract_const_name(node.children[0])
        full_name = (namespace + [name]).join("::")
        results << full_name
        results += extract_classes(node.children[2], namespace + [name])
      else
        node.children.each do |child|
          results += extract_classes(child, namespace)
        end
      end

      results
    end

    def extract_const_name(node)
      return nil unless node&.type == :const
      parent, name = node.children
      parent ? "#{extract_const_name(parent)}::#{name}" : name.to_s
    end

    def matches_pattern?(class_name)
      @config[:detect].any? do |pattern|
        if pattern[:namespace]
          class_name.start_with?(pattern[:namespace])
        elsif pattern[:suffix]
          class_name.end_with?(pattern[:suffix])
        else
          false
        end
      end
    end
  end

  # Query generator
  class QueryGenerator
    def initialize(config)
      @config = config
    end

    def generate(class_name)
      metric = @config[:rate_metric]
      handler_label = @config[:handler_label]
      labels = @config[:labels].map { |k, v| "#{k}=~\"#{v}\"" }
      labels << "#{handler_label}=\"#{class_name}\""

      "sum(#{metric}{#{labels.join(', ')}})"
    end
  end
end

# --- SPIKE TESTS ---

puts "=" * 60
puts "SPIKE: HTTP Metrics Detection"
puts "=" * 60
puts

# Test cases
test_cases = [
  {
    name: "Routes pattern (your style)",
    source: <<~RUBY
      module Routes
        module Users
          class Show
            def call
              # endpoint logic
            end
          end
        end
      end
    RUBY
  },
  {
    name: "Rails Controller",
    source: <<~RUBY
      class UsersController < ApplicationController
        def show
          @user = User.find(params[:id])
        end
        
        def create
          @user = User.create(user_params)
        end
      end
    RUBY
  },
  {
    name: "Grape API",
    source: <<~RUBY
      module API
        module V1
          class Users < Grape::API
            get ':id' do
              User.find(params[:id])
            end
          end
        end
      end
    RUBY
  },
  {
    name: "Non-matching class (should be ignored)",
    source: <<~RUBY
      class PaymentProcessor
        def process
          StatsD.increment("payments.processed")
        end
      end
    RUBY
  },
  {
    name: "Mixed file",
    source: <<~RUBY
      module Routes
        module Payments
          class Create
            def call
              processor = PaymentProcessor.new
              processor.process
            end
          end
        end
      end
      
      class PaymentProcessor
        def process
          logger.info("Processing payment")
        end
      end
    RUBY
  }
]

detector = Spike::ClassDetector.new(Spike::HTTP_METRICS_CONFIG)
generator = Spike::QueryGenerator.new(Spike::HTTP_METRICS_CONFIG)

test_cases.each do |tc|
  puts "Test: #{tc[:name]}"
  puts "-" * 40
  
  detected = detector.detect(tc[:source])
  
  if detected.empty?
    puts "  No HTTP endpoints detected"
  else
    detected.each do |class_name|
      puts "  Detected: #{class_name}"
      puts "  Query:    #{generator.generate(class_name)}"
    end
  end
  
  puts
end

puts "=" * 60
puts "SPIKE CONCLUSIONS"
puts "=" * 60
puts <<~CONCLUSIONS

  ✓ Can detect classes matching namespace patterns (Routes::*)
  ✓ Can detect classes matching suffix patterns (*Controller)  
  ✓ Can generate Prometheus queries from class names
  ✓ Config-driven approach is flexible for different frameworks
  
  Questions to resolve:
  
  1. For Controllers, do we need action names too?
     - "UsersController" vs "UsersController#show"
     - Depends on how Prometheus labels are set up
  
  2. Should this be a separate signal type (:http_endpoint)?
     Or extend existing detection?
  
  3. Panel generation: one panel per class, or grouped?
  
  4. What about latency/error metrics? Same pattern?

CONCLUSIONS
