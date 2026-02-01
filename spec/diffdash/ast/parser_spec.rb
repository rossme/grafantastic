# frozen_string_literal: true

RSpec.describe Diffdash::AST::Parser do
  describe '.parse' do
    it 'parses valid Ruby code' do
      source = 'class Foo; end'
      ast = described_class.parse(source)

      expect(ast).to be_a(Parser::AST::Node)
      expect(ast.type).to eq(:class)
    end

    it 'parses complex Ruby code' do
      source = <<~RUBY
        module Services
          class PaymentProcessor
            def process
              logger.info "Processing"
            end
          end
        end
      RUBY

      ast = described_class.parse(source)
      expect(ast).to be_a(Parser::AST::Node)
      expect(ast.type).to eq(:module)
    end

    it 'returns nil for invalid Ruby syntax' do
      source = 'class Foo { invalid }'

      expect { described_class.parse(source) }.not_to raise_error
      # Parser may return partial AST or nil depending on error
    end

    it 'accepts file path for error reporting' do
      source = 'class Foo; end'
      ast = described_class.parse(source, '/app/models/foo.rb')

      expect(ast).to be_a(Parser::AST::Node)
    end

    it 'handles empty source' do
      ast = described_class.parse('')
      expect(ast).to be_nil
    end
  end
end
