# frozen_string_literal: true

RSpec.describe Diffdash::Signal::Log do
  subject(:log_signal) do
    described_class.new(
      name: 'payment_processed',
      source_file: '/app/services/payment.rb',
      defining_class: 'PaymentProcessor',
      inheritance_depth: 0,
      metadata: { level: 'info', line: 42 }
    )
  end

  describe '#initialize' do
    it 'sets all attributes' do
      expect(log_signal.name).to eq('payment_processed')
      expect(log_signal.type).to eq(:log)
      expect(log_signal.source_file).to eq('/app/services/payment.rb')
      expect(log_signal.defining_class).to eq('PaymentProcessor')
      expect(log_signal.inheritance_depth).to eq(0)
      expect(log_signal.metadata).to eq({ level: 'info', line: 42 })
    end
  end

  describe '#log?' do
    it 'returns true' do
      expect(log_signal.log?).to be true
    end
  end

  describe '#metric?' do
    it 'returns false' do
      expect(log_signal.metric?).to be false
    end
  end

  describe '#event?' do
    it 'returns false' do
      expect(log_signal.event?).to be false
    end
  end

  describe '#level' do
    it 'returns the log level from metadata' do
      expect(log_signal.level).to eq('info')
    end
  end

  describe '#line' do
    it 'returns the line number from metadata' do
      expect(log_signal.line).to eq(42)
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      expect(log_signal.to_h).to include(
        type: :log,
        name: 'payment_processed',
        source_file: '/app/services/payment.rb',
        defining_class: 'PaymentProcessor',
        inheritance_depth: 0
      )
    end
  end
end
