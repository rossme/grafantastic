# frozen_string_literal: true

RSpec.describe Diffdash::AST::Visitor do
  describe 'interpolated log detection' do
    def log_calls_from(source)
      ast = Diffdash::AST::Parser.parse(source, 'test.rb')
      visitor = described_class.new(file_path: 'test.rb', inheritance_depth: 0)
      visitor.process(ast)
      visitor.log_calls
    end

    context 'with structured logs (literal strings)' do
      it 'marks them as not interpolated' do
        source = <<~RUBY
          Rails.logger.info("user_created")
        RUBY

        calls = log_calls_from(source)
        expect(calls.size).to eq(1)
        expect(calls.first[:interpolated]).to eq(false)
      end

      it 'marks symbol logs as not interpolated' do
        source = <<~RUBY
          Rails.logger.info(:user_created)
        RUBY

        calls = log_calls_from(source)
        expect(calls.size).to eq(1)
        expect(calls.first[:interpolated]).to eq(false)
      end
    end

    context 'with interpolated logs' do
      it 'marks them as interpolated' do
        source = <<~RUBY
          Rails.logger.info("User \#{user.id} created")
        RUBY

        calls = log_calls_from(source)
        expect(calls.size).to eq(1)
        expect(calls.first[:interpolated]).to eq(true)
      end

      it 'marks complex interpolations as interpolated' do
        source = <<~RUBY
          Rails.logger.warn("Processing \#{item.type} for \#{user.name}")
        RUBY

        calls = log_calls_from(source)
        expect(calls.size).to eq(1)
        expect(calls.first[:interpolated]).to eq(true)
      end
    end

    context 'with generic log methods' do
      it 'detects interpolation in logger.add calls' do
        source = <<~RUBY
          logger.add(Logger::INFO, "User \#{id} processed")
        RUBY

        calls = log_calls_from(source)
        expect(calls.size).to eq(1)
        expect(calls.first[:interpolated]).to eq(true)
      end

      it 'detects structured logs in logger.add calls' do
        source = <<~RUBY
          logger.add(Logger::INFO, "user_processed")
        RUBY

        calls = log_calls_from(source)
        expect(calls.size).to eq(1)
        expect(calls.first[:interpolated]).to eq(false)
      end
    end
  end
end
