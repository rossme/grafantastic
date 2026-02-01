# frozen_string_literal: true

RSpec.describe Diffdash::FileFilter do
  describe 'class methods' do
    describe '.filter' do
      it 'includes regular Ruby files' do
        files = ['/app/models/user.rb', '/app/services/payment.rb']
        expect(described_class.filter(files)).to eq(files)
      end

      it 'excludes _spec.rb files' do
        files = ['/app/models/user.rb', '/spec/models/user_spec.rb']
        expect(described_class.filter(files)).to eq(['/app/models/user.rb'])
      end

      it 'excludes _test.rb files' do
        files = ['/app/models/user.rb', '/test/models/user_test.rb']
        expect(described_class.filter(files)).to eq(['/app/models/user.rb'])
      end

      it 'excludes files in /spec/ directory' do
        files = ['/app/models/user.rb', '/spec/support/helpers.rb']
        expect(described_class.filter(files)).to eq(['/app/models/user.rb'])
      end

      it 'excludes files in /test/ directory' do
        files = ['/app/models/user.rb', '/test/fixtures/data.rb']
        expect(described_class.filter(files)).to eq(['/app/models/user.rb'])
      end

      it 'excludes files in /config/ directory' do
        files = ['/app/models/user.rb', '/config/initializers/sidekiq.rb']
        expect(described_class.filter(files)).to eq(['/app/models/user.rb'])
      end

      it 'excludes non-Ruby files' do
        files = ['/app/models/user.rb', '/README.md', '/config.yml', '/data.json']
        expect(described_class.filter(files)).to eq(['/app/models/user.rb'])
      end

      it 'returns empty array when all files are excluded' do
        files = ['/spec/models/user_spec.rb', '/test/models/user_test.rb']
        expect(described_class.filter(files)).to eq([])
      end

      it 'handles empty input' do
        expect(described_class.filter([])).to eq([])
      end
    end

    describe '.include_file?' do
      it 'returns true for regular Ruby application files' do
        expect(described_class.include_file?('/app/models/user.rb')).to be true
        expect(described_class.include_file?('/lib/diffdash/parser.rb')).to be true
      end

      it 'returns false for spec files' do
        expect(described_class.include_file?('/spec/models/user_spec.rb')).to be false
      end

      it 'returns false for test files' do
        expect(described_class.include_file?('/test/models/user_test.rb')).to be false
      end

      it 'returns false for config files' do
        expect(described_class.include_file?('/config/application.rb')).to be false
      end

      it 'returns false for non-Ruby files' do
        expect(described_class.include_file?('/README.md')).to be false
        expect(described_class.include_file?('/config.yml')).to be false
      end
    end
  end

  describe 'instance methods with config' do
    let(:config) { double('Config') }

    before do
      allow(config).to receive(:excluded_suffixes).and_return(%w[_spec.rb _test.rb])
      allow(config).to receive(:excluded_directories).and_return(%w[spec test config])
      allow(config).to receive(:ignore_paths).and_return([])
      allow(config).to receive(:include_paths).and_return([])
    end

    describe '#filter' do
      subject(:filter) { described_class.new(config: config) }

      it 'includes regular Ruby files' do
        files = ['/app/models/user.rb', '/app/services/payment.rb']
        expect(filter.filter(files)).to eq(files)
      end

      it 'excludes files based on configured suffixes' do
        allow(config).to receive(:excluded_suffixes).and_return(%w[_spec.rb _integration.rb])
        files = ['/app/models/user.rb', '/spec/user_spec.rb', '/test/user_integration.rb']
        expect(filter.filter(files)).to eq(['/app/models/user.rb'])
      end

      it 'excludes files based on configured directories' do
        allow(config).to receive(:excluded_directories).and_return(%w[spec vendor])
        files = ['/app/models/user.rb', '/spec/user_spec.rb', '/vendor/bundle/gems.rb']
        expect(filter.filter(files)).to eq(['/app/models/user.rb'])
      end
    end

    describe '#include_file? with ignore_paths' do
      subject(:filter) { described_class.new(config: config) }

      it 'excludes files matching ignore_paths patterns' do
        allow(config).to receive(:ignore_paths).and_return(['vendor/', 'lib/legacy/'])
        expect(filter.include_file?('/vendor/bundle/active_record.rb')).to be false
        expect(filter.include_file?('/lib/legacy/old_code.rb')).to be false
        expect(filter.include_file?('/app/models/user.rb')).to be true
      end

      it 'supports glob patterns in ignore_paths' do
        allow(config).to receive(:ignore_paths).and_return(['lib/**/*_old.rb'])
        expect(filter.include_file?('lib/utils/parser_old.rb')).to be false
        expect(filter.include_file?('lib/utils/parser.rb')).to be true
      end

      it 'matches paths containing the pattern' do
        allow(config).to receive(:ignore_paths).and_return(['legacy'])
        expect(filter.include_file?('/app/legacy/code.rb')).to be false
        expect(filter.include_file?('/lib/legacy/utils.rb')).to be false
        expect(filter.include_file?('/app/models/user.rb')).to be true
      end
    end

    describe '#include_file? with include_paths' do
      subject(:filter) { described_class.new(config: config) }

      it 'only includes files matching include_paths when configured' do
        allow(config).to receive(:include_paths).and_return(['app/', 'lib/'])
        expect(filter.include_file?('/app/models/user.rb')).to be true
        expect(filter.include_file?('/lib/utils/parser.rb')).to be true
        expect(filter.include_file?('/bin/script.rb')).to be false
      end

      it 'includes all files when include_paths is empty' do
        allow(config).to receive(:include_paths).and_return([])
        expect(filter.include_file?('/app/models/user.rb')).to be true
        expect(filter.include_file?('/bin/script.rb')).to be true
      end

      it 'supports glob patterns in include_paths' do
        allow(config).to receive(:include_paths).and_return(['app/**/*.rb'])
        expect(filter.include_file?('app/models/user.rb')).to be true
        expect(filter.include_file?('lib/utils/parser.rb')).to be false
      end
    end

    describe '#include_file? with combined filters' do
      subject(:filter) { described_class.new(config: config) }

      it 'applies all filters in order' do
        allow(config).to receive(:ignore_paths).and_return(['vendor/'])
        allow(config).to receive(:include_paths).and_return(['app/', 'lib/'])

        # Included by include_paths, not in ignore_paths
        expect(filter.include_file?('/app/models/user.rb')).to be true

        # Not in include_paths
        expect(filter.include_file?('/bin/script.rb')).to be false

        # In ignore_paths (even though it might match include_paths)
        expect(filter.include_file?('/vendor/bundle/active.rb')).to be false

        # Excluded by suffix
        expect(filter.include_file?('/app/models/user_spec.rb')).to be false

        # Excluded by directory
        expect(filter.include_file?('/spec/models/user.rb')).to be false
      end
    end

    describe 'custom excluded_directories regex building' do
      it 'handles empty excluded_directories' do
        allow(config).to receive(:excluded_directories).and_return([])
        filter = described_class.new(config: config)
        expect(filter.include_file?('/spec/user_spec.rb')).to be false # Still excluded by suffix
        expect(filter.include_file?('/spec/support/helpers.rb')).to be true # Directory not excluded
      end

      it 'escapes special regex characters in directory names' do
        allow(config).to receive(:excluded_directories).and_return(['spec.d', 'test+files'])
        filter = described_class.new(config: config)
        expect(filter.include_file?('/spec.d/helpers.rb')).to be false
        expect(filter.include_file?('/test+files/data.rb')).to be false
        expect(filter.include_file?('/specd/helpers.rb')).to be true # Not matching unescaped
      end
    end
  end
end
