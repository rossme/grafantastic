# frozen_string_literal: true

RSpec.describe Diffdash::Linter::Runner do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(temp_dir)
  end

  def create_file(name, content)
    path = File.join(temp_dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  describe '#run' do
    subject(:runner) { described_class.new }

    context 'with files containing interpolated logs' do
      it 'returns issues for each interpolated log' do
        file = create_file('user_service.rb', <<~RUBY)
          class UserService
            def create(user)
              logger.info("User \#{user.id} created")
              logger.info("user_created") # This is fine
            end
          end
        RUBY

        issues = runner.run([file])

        expect(issues.size).to eq(1)
        expect(issues.first.rule).to eq('interpolated-logs')
      end
    end

    context 'with files containing only structured logs' do
      it 'returns no issues' do
        file = create_file('clean_service.rb', <<~RUBY)
          class CleanService
            def process
              logger.info("process_started")
              logger.info(:process_complete)
            end
          end
        RUBY

        issues = runner.run([file])

        expect(issues).to be_empty
      end
    end

    context 'with multiple files' do
      it 'analyzes all files' do
        file1 = create_file('service_a.rb', <<~RUBY)
          logger.info("User \#{id} logged in")
        RUBY

        file2 = create_file('service_b.rb', <<~RUBY)
          logger.error("Order \#{order.id} failed")
        RUBY

        issues = runner.run([file1, file2])

        expect(issues.size).to eq(2)
        files = issues.map(&:file)
        expect(files).to include(file1)
        expect(files).to include(file2)
      end
    end

    context 'with syntax errors in files' do
      it 'skips unparseable files without crashing' do
        bad_file = create_file('broken.rb', 'def foo(')
        good_file = create_file('good.rb', 'logger.info("User #{id}")')

        issues = runner.run([bad_file, good_file])

        expect(issues.size).to eq(1)
        expect(issues.first.file).to eq(good_file)
      end
    end

    context 'with non-existent files' do
      it 'skips missing files without crashing' do
        good_file = create_file('exists.rb', 'logger.info("User #{id}")')

        issues = runner.run(['/nonexistent/file.rb', good_file])

        expect(issues.size).to eq(1)
      end
    end
  end

  describe '#run_on_change_set' do
    subject(:runner) { described_class.new }

    it 'delegates to #run with filtered files' do
      file = create_file('service.rb', 'logger.info("User #{id}")')

      change_set = instance_double(
        Diffdash::Engine::ChangeSet,
        filtered_files: [file]
      )

      issues = runner.run_on_change_set(change_set)

      expect(issues.size).to eq(1)
    end
  end

  describe '#issues_by_rule' do
    subject(:runner) { described_class.new }

    it 'groups issues by rule name' do
      file = create_file('service.rb', <<~RUBY)
        logger.info("User \#{id} created")
        logger.error("Order \#{order_id} failed")
      RUBY

      runner.run([file])

      grouped = runner.issues_by_rule
      expect(grouped['interpolated-logs'].size).to eq(2)
    end
  end

  describe '#issue_count' do
    subject(:runner) { described_class.new }

    it 'returns total issue count' do
      file = create_file('service.rb', <<~RUBY)
        logger.info("User \#{id}")
        logger.warn("Order \#{oid}")
      RUBY

      runner.run([file])

      expect(runner.issue_count).to eq(2)
    end
  end
end
