# frozen_string_literal: true

RSpec.describe Diffdash::Linter::Formatter do
  let(:issue) do
    Diffdash::Linter::Base::Issue.new(
      rule: 'interpolated-logs',
      file: '/app/services/user_service.rb',
      line: 42,
      message: 'Log uses string interpolation',
      suggestion: 'logger.info("user_created", user_id: user_id)',
      context: {
        original: 'logger.info("User #{user.id} created")',
        static_match: 'User  created',
        interpolation_count: 1
      }
    )
  end

  describe '#format' do
    context 'with no issues' do
      subject(:formatter) { described_class.new([]) }

      it 'returns success message' do
        output = formatter.format

        expect(output).to include('No lint issues found')
        expect(output).to include('look good')
      end
    end

    context 'with issues (non-verbose)' do
      subject(:formatter) { described_class.new([issue], verbose: false) }

      it 'shows summary count' do
        output = formatter.format

        expect(output).to include('Found 1 log with string interpolation')
      end

      it 'shows example' do
        output = formatter.format

        expect(output).to include('Before:')
        expect(output).to include('After:')
        expect(output).to include('structured logging')
      end

      it 'suggests verbose mode' do
        output = formatter.format

        expect(output).to include('diffdash lint --verbose')
      end
    end

    context 'with issues (verbose)' do
      subject(:formatter) { described_class.new([issue], verbose: true) }

      it 'shows file and line' do
        output = formatter.format

        expect(output).to include('user_service.rb:42')
      end

      it 'shows original code' do
        output = formatter.format

        expect(output).to include('User')
        expect(output).to include('created')
      end

      it 'shows static match' do
        output = formatter.format

        expect(output).to include('Matches:')
        expect(output).to include('User  created')
      end

      it 'shows suggestion' do
        output = formatter.format

        expect(output).to include('Suggested:')
        expect(output).to include('user_created')
      end

      it 'shows summary' do
        output = formatter.format

        expect(output).to include('Summary:')
        expect(output).to include('1 interpolated log')
      end
    end

    context 'with multiple issues' do
      let(:issues) do
        [
          issue,
          Diffdash::Linter::Base::Issue.new(
            rule: 'interpolated-logs',
            file: '/app/services/order_service.rb',
            line: 15,
            message: 'Log uses string interpolation',
            suggestion: 'logger.error("order_failed", order_id: order_id)',
            context: {
              original: 'logger.error("Order #{order.id} failed")',
              static_match: 'Order  failed',
              interpolation_count: 1
            }
          )
        ]
      end

      subject(:formatter) { described_class.new(issues, verbose: false) }

      it 'pluralizes correctly' do
        output = formatter.format

        expect(output).to include('Found 2 logs with string interpolation')
      end
    end
  end
end
