# frozen_string_literal: true

RSpec.describe Grafantastic::AST::Visitor do
  let(:file_path) { "/app/services/payment.rb" }
  let(:inheritance_depth) { 0 }

  subject(:visitor) { described_class.new(file_path: file_path, inheritance_depth: inheritance_depth) }

  def parse_and_visit(source)
    ast = Grafantastic::AST::Parser.parse(source, file_path)
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

      it "derives event name from message string" do
        source = <<~RUBY
          class Foo
            def bar
              logger.info "Processing payment for user"
            end
          end
        RUBY
        parse_and_visit(source)

        expect(visitor.log_calls.first[:event_name]).to eq("processing_payment_for_user")
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
  end
end
