# frozen_string_literal: true

RSpec.describe Diffdash::Formatters::DashboardTitle do
  describe '.sanitize' do
    it 'preserves alphanumeric characters' do
      result = described_class.sanitize('feature-123')
      expect(result).to eq('feature-123')
    end

    it 'preserves underscores' do
      result = described_class.sanitize('feature_branch_name')
      expect(result).to eq('feature_branch_name')
    end

    it 'preserves hyphens' do
      result = described_class.sanitize('feature-branch-name')
      expect(result).to eq('feature-branch-name')
    end

    it 'replaces special characters with hyphens' do
      result = described_class.sanitize('feature/branch@name')
      expect(result).to eq('feature-branch-name')
    end

    it 'collapses multiple hyphens into one' do
      result = described_class.sanitize('feature---branch')
      expect(result).to eq('feature-branch')
    end

    it 'removes leading hyphens' do
      result = described_class.sanitize('-feature-branch')
      expect(result).to eq('feature-branch')
    end

    it 'removes trailing hyphens' do
      result = described_class.sanitize('feature-branch-')
      expect(result).to eq('feature-branch')
    end

    it 'truncates to 40 characters' do
      long_name = 'a' * 50
      result = described_class.sanitize(long_name)

      expect(result.length).to eq(40)
    end

    it 'uses fallback for empty sanitized name' do
      result = described_class.sanitize('///')
      expect(result).to eq('pr-dashboard')
    end

    it 'uses fallback for empty input' do
      result = described_class.sanitize('')
      expect(result).to eq('pr-dashboard')
    end

    it 'handles complex real-world branch names' do
      result = described_class.sanitize('feature/JIRA-123/add-payment-gateway')
      expect(result).to eq('feature-JIRA-123-add-payment-gateway')
    end

    it 'handles branch names with spaces' do
      result = described_class.sanitize('feature branch name')
      expect(result).to eq('feature-branch-name')
    end

    it 'handles unicode characters' do
      result = described_class.sanitize('feature-branch-émoji-🚀')
      expect(result).to eq('feature-branch-moji')
    end

    it 'is deterministic' do
      input = 'feature/test-branch'
      result1 = described_class.sanitize(input)
      result2 = described_class.sanitize(input)

      expect(result1).to eq(result2)
    end

    describe 'architectural boundaries' do
      it 'is a pure function - no side effects' do
        # Calling sanitize should not modify any state
        input = 'test-branch'
        described_class.sanitize(input)

        expect(input).to eq('test-branch') # Original unchanged
      end

      it 'has no dependencies on other layers' do
        # Should be a simple string transformation
        # No detector, renderer, or client knowledge
        expect(described_class).not_to respond_to(:detect)
        expect(described_class).not_to respond_to(:render)
        expect(described_class).not_to respond_to(:upload)
      end
    end
  end
end
