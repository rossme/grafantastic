# frozen_string_literal: true

RSpec.describe Diffdash::Linter::InterpolatedLogs do
  subject(:rule) { described_class.new }

  describe "#rule_name" do
    it "returns the rule identifier" do
      expect(rule.rule_name).to eq("interpolated-logs")
    end
  end

  describe "#check" do
    def log_calls_from(source)
      ast = Diffdash::AST::Parser.parse(source)
      visitor = Diffdash::AST::Visitor.new(file_path: "test.rb", inheritance_depth: 0)
      visitor.process(ast)
      visitor.log_calls
    end

    context "with interpolated string" do
      let(:source) do
        <<~RUBY
          class UserService
            def create(user)
              logger.info("User \#{user.id} logged in")
            end
          end
        RUBY
      end

      it "returns an issue" do
        log_call = log_calls_from(source).first
        issue = rule.check(log_call, "app/services/user_service.rb")

        expect(issue).not_to be_nil
        expect(issue.rule).to eq("interpolated-logs")
        expect(issue.file).to eq("app/services/user_service.rb")
      end

      it "includes the original string in context" do
        log_call = log_calls_from(source).first
        issue = rule.check(log_call, "test.rb")

        expect(issue.context[:original]).to include("User")
        expect(issue.context[:original]).to include("logged in")
      end

      it "includes static match in context" do
        log_call = log_calls_from(source).first
        issue = rule.check(log_call, "test.rb")

        expect(issue.context[:static_match]).to eq("User  logged in")
      end

      it "suggests structured logging" do
        log_call = log_calls_from(source).first
        issue = rule.check(log_call, "test.rb")

        expect(issue.suggestion).to include("logger.info")
        expect(issue.suggestion).to include("user_id")
      end
    end

    context "with plain string" do
      let(:source) do
        <<~RUBY
          class UserService
            def create(user)
              logger.info("user_created")
            end
          end
        RUBY
      end

      it "returns nil (no issue)" do
        log_call = log_calls_from(source).first
        issue = rule.check(log_call, "test.rb")

        expect(issue).to be_nil
      end
    end

    context "with symbol" do
      let(:source) do
        <<~RUBY
          class UserService
            def create(user)
              logger.info(:user_created)
            end
          end
        RUBY
      end

      it "returns nil (no issue)" do
        log_call = log_calls_from(source).first
        issue = rule.check(log_call, "test.rb")

        expect(issue).to be_nil
      end
    end

    context "with multiple interpolations" do
      let(:source) do
        <<~RUBY
          class OrderService
            def process(order, user)
              logger.error("Order \#{order.id} failed for user \#{user.email}")
            end
          end
        RUBY
      end

      it "counts all interpolations" do
        log_call = log_calls_from(source).first
        issue = rule.check(log_call, "test.rb")

        expect(issue.context[:interpolation_count]).to eq(2)
      end

      it "includes all variables in suggestion" do
        log_call = log_calls_from(source).first
        issue = rule.check(log_call, "test.rb")

        expect(issue.suggestion).to include("order_id")
        expect(issue.suggestion).to include("user_email")
      end
    end

    context "with Rails.logger" do
      let(:source) do
        <<~RUBY
          class PaymentService
            def charge(amount)
              Rails.logger.warn("Charging \#{amount} cents")
            end
          end
        RUBY
      end

      it "detects interpolation in Rails.logger calls" do
        log_call = log_calls_from(source).first
        issue = rule.check(log_call, "test.rb")

        expect(issue).not_to be_nil
        expect(issue.context[:original]).to include("Charging")
      end
    end

    context "with local variable interpolation" do
      let(:source) do
        <<~RUBY
          def process
            count = 5
            logger.info("Processed \#{count} items")
          end
        RUBY
      end

      it "extracts variable name" do
        log_call = log_calls_from(source).first
        issue = rule.check(log_call, "test.rb")

        expect(issue.suggestion).to include("count")
      end
    end
  end
end
