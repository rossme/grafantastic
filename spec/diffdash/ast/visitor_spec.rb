# frozen_string_literal: true

RSpec.describe Diffdash::AST::Visitor do
  let(:file_path) { "/app/services/payment.rb" }
  let(:inheritance_depth) { 0 }

  subject(:visitor) { described_class.new(file_path: file_path, inheritance_depth: inheritance_depth) }

  def parse_and_visit(source)
    ast = Diffdash::AST::Parser.parse(source, file_path)
    visitor.process(ast)
    visitor
  end

  describe "#process" do
    context "with class definitions" do
      it "extracts class name" do
        source = "class PaymentProcessor; end"
        parse_and_visit(source)

        expect(visitor.class_definitions.size).to eq(1)
        expect(visitor.class_definitions.first[:name]).to eq("PaymentProcessor")
      end

      it "extracts parent class name" do
        source = "class PaymentProcessor < BaseProcessor; end"
        parse_and_visit(source)

        expect(visitor.class_definitions.first[:parent]).to eq("BaseProcessor")
      end

      it "handles namespaced classes" do
        source = <<~RUBY
          module Services
            class PaymentProcessor
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.class_definitions.first[:name]).to eq("Services::PaymentProcessor")
      end

      it "handles nested classes" do
        source = <<~RUBY
          class Outer
            class Inner
            end
          end
        RUBY
        parse_and_visit(source)

        names = visitor.class_definitions.map { |c| c[:name] }
        expect(names).to include("Outer", "Outer::Inner")
      end
    end

    context "with log calls" do
      it "detects logger.info calls" do
        source = <<~RUBY
          class Foo
            def bar
              logger.info "Processing request"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.size).to eq(1)
        expect(visitor.log_calls.first[:level]).to eq("info")
      end

      it "detects logger.error calls" do
        source = <<~RUBY
          class Foo
            def bar
              logger.error "Something went wrong"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.first[:level]).to eq("error")
      end

      it "detects logger.warn calls" do
        source = <<~RUBY
          class Foo
            def bar
              logger.warn "Warning message"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.first[:level]).to eq("warn")
      end

      it "detects Rails.logger calls" do
        source = <<~RUBY
          class Foo
            def bar
              Rails.logger.info "Rails logging"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.size).to eq(1)
        expect(visitor.log_calls.first[:level]).to eq("info")
      end

      it "extracts event name from string literal" do
        source = <<~RUBY
          class Foo
            def bar
              logger.info "payment_processed"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.first[:event_name]).to eq("payment_processed")
      end

      it "extracts event name from symbol" do
        source = <<~RUBY
          class Foo
            def bar
              logger.info :payment_processed
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.first[:event_name]).to eq("payment_processed")
      end

      it "uses raw event name from message string" do
        source = <<~RUBY
          class Foo
            def bar
              logger.info "Processing payment for user"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.first[:event_name]).to eq("Processing payment for user")
      end

      it "derives event name from interpolated string" do
        source = <<~'RUBY'
          class Foo
            def bar(user_id)
              logger.info "Processed user #{user_id}"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.first[:event_name]).to eq("processed_user")
      end

      it "records defining class" do
        source = <<~RUBY
          class PaymentProcessor
            def process
              logger.info "Processing"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.first[:defining_class]).to eq("PaymentProcessor")
      end

      it "detects multiple log calls" do
        source = <<~RUBY
          class Foo
            def bar
              logger.info "Start"
              logger.debug "Details"
              logger.error "Failed"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.size).to eq(3)
        levels = visitor.log_calls.map { |l| l[:level] }
        expect(levels).to eq(%w[info debug error])
      end

      it "detects logger.unknown calls" do
        source = <<~RUBY
          class Foo
            def bar
              logger.unknown "Unknown severity message"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.size).to eq(1)
        expect(visitor.log_calls.first[:level]).to eq("unknown")
      end

      it "detects logger.add with symbol severity" do
        source = <<~RUBY
          class Foo
            def bar
              logger.add(:info, "message via add")
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.size).to eq(1)
        expect(visitor.log_calls.first[:level]).to eq("info")
        expect(visitor.log_calls.first[:event_name]).to eq("message via add")
      end

      it "detects logger.log with symbol severity" do
        source = <<~RUBY
          class Foo
            def bar
              logger.log(:error, "message via log")
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.size).to eq(1)
        expect(visitor.log_calls.first[:level]).to eq("error")
        expect(visitor.log_calls.first[:event_name]).to eq("message via log")
      end

      it "detects logger.add with Logger constant severity" do
        source = <<~RUBY
          class Foo
            def bar
              logger.add(Logger::WARN, "warning message")
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.size).to eq(1)
        expect(visitor.log_calls.first[:level]).to eq("warn")
      end

      it "detects logger.add with numeric severity" do
        source = <<~RUBY
          class Foo
            def bar
              logger.add(2, "warn level message")
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.size).to eq(1)
        expect(visitor.log_calls.first[:level]).to eq("warn")
      end

      it "detects constant logger objects" do
        source = <<~RUBY
          class Foo
            LOG = Logger.new(STDOUT)
            
            def bar
              LOG.info "Using constant logger"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.size).to eq(1)
        expect(visitor.log_calls.first[:level]).to eq("info")
      end

      it "detects LOGGER constant" do
        source = <<~RUBY
          class Foo
            LOGGER = Logger.new(STDERR)
            
            def bar
              LOGGER.error "Error via LOGGER constant"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.size).to eq(1)
        expect(visitor.log_calls.first[:level]).to eq("error")
      end

      it "detects class variable logger" do
        source = <<~RUBY
          class Foo
            @@logger = Logger.new(STDOUT)
            
            def bar
              @@logger.info "Class variable logger"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.size).to eq(1)
        expect(visitor.log_calls.first[:level]).to eq("info")
      end
    end

    context "with metric calls" do
      it "detects StatsD.increment calls" do
        source = <<~RUBY
          class Foo
            def bar
              StatsD.increment("payments.processed")
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.size).to eq(1)
        expect(visitor.metric_calls.first[:name]).to eq("payments.processed")
        expect(visitor.metric_calls.first[:metric_type]).to eq(:counter)
      end

      it "detects Statsd.increment calls (lowercase d)" do
        source = <<~RUBY
          class Foo
            def bar
              Statsd.increment("payments.processed")
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.size).to eq(1)
      end

      it "detects Datadog.increment calls" do
        source = <<~RUBY
          class Foo
            def bar
              Datadog.increment("payments.processed")
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.size).to eq(1)
        expect(visitor.metric_calls.first[:name]).to eq("payments.processed")
        expect(visitor.metric_calls.first[:metric_type]).to eq(:counter)
      end

      it "detects DogStatsD.increment calls" do
        source = <<~RUBY
          class Foo
            def bar
              DogStatsD.increment("events.count")
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.size).to eq(1)
        expect(visitor.metric_calls.first[:name]).to eq("events.count")
        expect(visitor.metric_calls.first[:metric_type]).to eq(:counter)
      end

      it "detects Datadog.gauge calls" do
        source = <<~RUBY
          class Foo
            def bar
              Datadog.gauge("queue.size", 42)
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.size).to eq(1)
        expect(visitor.metric_calls.first[:name]).to eq("queue.size")
        expect(visitor.metric_calls.first[:metric_type]).to eq(:gauge)
      end

      it "detects Datadog.timing calls" do
        source = <<~RUBY
          class Foo
            def bar
              Datadog.timing("request.duration", 150)
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.size).to eq(1)
        expect(visitor.metric_calls.first[:name]).to eq("request.duration")
        expect(visitor.metric_calls.first[:metric_type]).to eq(:histogram)
      end

      it "detects Prometheus.counter calls" do
        source = <<~RUBY
          class Foo
            def bar
              Prometheus.counter(:payments_total).increment
            end
          end
        RUBY
        parse_and_visit(source)

        # Chained calls may be detected at multiple points
        counter_calls = visitor.metric_calls.select { |c| c[:name] == "payments_total" }
        expect(counter_calls).not_to be_empty
        expect(counter_calls.first[:metric_type]).to eq(:counter)
      end

      it "detects Prometheus.histogram calls" do
        source = <<~RUBY
          class Foo
            def bar
              Prometheus.histogram(:request_duration).observe(0.5)
            end
          end
        RUBY
        parse_and_visit(source)

        histogram_calls = visitor.metric_calls.select { |c| c[:name] == "request_duration" }
        expect(histogram_calls).not_to be_empty
        expect(histogram_calls.first[:metric_type]).to eq(:histogram)
      end

      it "detects Prometheus.gauge calls" do
        source = <<~RUBY
          class Foo
            def bar
              Prometheus.gauge(:queue_size).set(100)
            end
          end
        RUBY
        parse_and_visit(source)

        gauge_calls = visitor.metric_calls.select { |c| c[:name] == "queue_size" }
        expect(gauge_calls).not_to be_empty
        expect(gauge_calls.first[:metric_type]).to eq(:gauge)
      end

      it "detects Hesiod.emit calls" do
        source = <<~RUBY
          class Foo
            def bar
              Hesiod.emit(:latency_ms, 42)
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.size).to eq(1)
        expect(visitor.metric_calls.first[:name]).to eq("latency_ms")
      end

      it "detects StatsD.timing calls as histogram" do
        source = <<~RUBY
          class Foo
            def bar
              StatsD.timing("request.duration", 150)
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.first[:metric_type]).to eq(:histogram)
      end

      it "records defining class for metrics" do
        source = <<~RUBY
          class PaymentProcessor
            def process
              StatsD.increment("payments.processed")
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.first[:defining_class]).to eq("PaymentProcessor")
      end
    end

    context "with dynamic metric names" do
      it "detects dynamic metric calls with variable names" do
        source = <<~RUBY
          class RecordProcessor
            def process(entity)
              Prometheus.counter(entity.id).increment
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls).to be_empty
        expect(visitor.dynamic_metric_calls.size).to eq(1)
        expect(visitor.dynamic_metric_calls.first[:metric_type]).to eq(:counter)
        expect(visitor.dynamic_metric_calls.first[:receiver]).to eq("Prometheus")
        expect(visitor.dynamic_metric_calls.first[:defining_class]).to eq("RecordProcessor")
      end

      it "detects dynamic StatsD calls" do
        source = <<~RUBY
          class Foo
            def bar(metric_name)
              StatsD.increment(metric_name)
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls).to be_empty
        expect(visitor.dynamic_metric_calls.size).to eq(1)
        expect(visitor.dynamic_metric_calls.first[:receiver]).to eq("StatsD")
      end

      it "does not double-count chained dynamic calls" do
        source = <<~RUBY
          class Foo
            def bar
              Prometheus.counter(some_method).increment
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.dynamic_metric_calls.size).to eq(1)
      end

      it "separates static and dynamic metric calls" do
        source = <<~RUBY
          class Foo
            def bar
              Prometheus.counter(:static_metric).increment
              Prometheus.counter(dynamic_name).increment
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.size).to eq(1)
        expect(visitor.metric_calls.first[:name]).to eq("static_metric")
        expect(visitor.dynamic_metric_calls.size).to eq(1)
      end
    end

    context "with module definitions" do
      it "extracts module definitions" do
        source = <<~RUBY
          module Loggable
            def log_action
              logger.info "action_performed"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.module_definitions.size).to eq(1)
        expect(visitor.module_definitions.first[:name]).to eq("Loggable")
      end

      it "extracts nested module definitions" do
        source = <<~RUBY
          module Concerns
            module Loggable
              def log_action
                logger.info "action_performed"
              end
            end
          end
        RUBY
        parse_and_visit(source)

        names = visitor.module_definitions.map { |m| m[:name] }
        expect(names).to include("Concerns", "Concerns::Loggable")
      end

      it "extracts signals from module methods" do
        source = <<~RUBY
          module Trackable
            def track_event
              StatsD.increment("events.tracked")
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.size).to eq(1)
        expect(visitor.metric_calls.first[:defining_class]).to eq("Trackable")
      end
    end

    context "with module inclusions" do
      it "detects include statements" do
        source = <<~RUBY
          class PaymentProcessor
            include Loggable
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.included_modules.size).to eq(1)
        expect(visitor.included_modules.first[:module_name]).to eq("Loggable")
        expect(visitor.included_modules.first[:including_class]).to eq("PaymentProcessor")
      end

      it "detects multiple includes" do
        source = <<~RUBY
          class PaymentProcessor
            include Loggable
            include Trackable
            include Concerns::Retryable
          end
        RUBY
        parse_and_visit(source)

        module_names = visitor.included_modules.map { |m| m[:module_name] }
        expect(module_names).to eq(["Loggable", "Trackable", "Concerns::Retryable"])
      end

      it "detects include with multiple modules on one line" do
        source = <<~RUBY
          class PaymentProcessor
            include Loggable, Trackable
          end
        RUBY
        parse_and_visit(source)

        module_names = visitor.included_modules.map { |m| m[:module_name] }
        expect(module_names).to eq(["Loggable", "Trackable"])
      end

      it "detects prepend statements" do
        source = <<~RUBY
          class PaymentProcessor
            prepend Retryable
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.prepended_modules.size).to eq(1)
        expect(visitor.prepended_modules.first[:module_name]).to eq("Retryable")
      end

      it "detects extend statements" do
        source = <<~RUBY
          class PaymentProcessor
            extend ClassMethods
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.extended_modules.size).to eq(1)
        expect(visitor.extended_modules.first[:module_name]).to eq("ClassMethods")
      end

      it "tracks inclusion context correctly in nested classes" do
        source = <<~RUBY
          module Services
            class PaymentProcessor
              include Loggable
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.included_modules.first[:including_class]).to eq("Services::PaymentProcessor")
      end
    end

    context "with inline namespaced classes" do
      it "handles inline namespace class definitions" do
        source = <<~RUBY
          class Admin::UsersController < Admin::BaseController
            def index
              logger.info "listing_users"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.class_definitions.first[:name]).to eq("Admin::UsersController")
        expect(visitor.class_definitions.first[:parent]).to eq("Admin::BaseController")
      end

      it "handles deeply namespaced inline classes" do
        source = <<~RUBY
          class Services::Payments::StripeProcessor < Services::Payments::BaseProcessor
            def charge
              StatsD.increment("stripe.charges")
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.class_definitions.first[:name]).to eq("Services::Payments::StripeProcessor")
        expect(visitor.class_definitions.first[:parent]).to eq("Services::Payments::BaseProcessor")
        expect(visitor.metric_calls.first[:defining_class]).to eq("Services::Payments::StripeProcessor")
      end
    end

    context "with Rails concerns" do
      it "extracts signals from ActiveSupport::Concern modules" do
        source = <<~RUBY
          module Trackable
            extend ActiveSupport::Concern

            def track_action
              StatsD.increment("actions.tracked")
              logger.info "action_tracked"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.metric_calls.size).to eq(1)
        expect(visitor.log_calls.size).to eq(1)
        expect(visitor.extended_modules.first[:module_name]).to eq("ActiveSupport::Concern")
      end

      it "extracts signals from included blocks" do
        source = <<~RUBY
          module Trackable
            extend ActiveSupport::Concern

            included do
              logger.info "module_included"
            end

            def track
              StatsD.increment("tracked")
            end
          end
        RUBY
        parse_and_visit(source)

        # The logger.info inside `included do` is still a send node we should capture
        log_events = visitor.log_calls.map { |l| l[:event_name] }
        expect(log_events).to include("module_included")
      end
    end
  end
end
