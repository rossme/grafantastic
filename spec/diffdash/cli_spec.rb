# frozen_string_literal: true

RSpec.describe Diffdash::CLI::Runner do
  let(:git_context) { instance_double(Diffdash::GitContext) }

  before do
    allow(Diffdash::GitContext).to receive(:new).and_return(git_context)
    allow(git_context).to receive(:branch_name).and_return("feature-branch")
    allow(git_context).to receive(:changed_files).and_return([])
  end

  describe ".run" do
    it "creates new instance and calls execute" do
      expect(described_class.run(["--dry-run"])).to eq(0)
    end
  end

  describe "#execute" do
    context "with --help flag" do
      it "prints help and returns 0" do
        expect { described_class.run(["--help"]) }.to output(/Usage:/).to_stdout
      end

      it "returns 0 exit code" do
        expect(described_class.run(["--help"])).to eq(0)
      end
    end

    context "with -h flag" do
      it "prints help" do
        expect { described_class.run(["-h"]) }.to output(/Usage:/).to_stdout
      end
    end

    context "with invalid arguments" do
      it "returns exit code 1" do
        result = silence_stderr { described_class.run(["-dry-run"]) }
        expect(result).to eq(1)
      end

      it "outputs error message to stderr" do
        expect { described_class.run(["-dry-run"]) }.to output(/Unknown argument.*-dry-run/).to_stderr
      end

      it "suggests using --help" do
        expect { described_class.run(["--unknown"]) }.to output(/diffdash --help/).to_stderr
      end

      it "lists all invalid arguments" do
        expect { described_class.run(["--foo", "-x"]) }.to output(/--foo.*-x/).to_stderr
      end

      it "still shows help when --help is included with invalid args" do
        expect { described_class.run(["--help", "--invalid"]) }.to output(/Usage:/).to_stdout
      end
    end

    context "with no changed files" do
      it "does not generate a dashboard" do
        output = capture_stdout { described_class.run(["--dry-run"]) }

        expect(output).to be_empty
      end

      it "outputs no signals message to stderr" do
        expect { described_class.run(["--dry-run"]) }.to output(/No observability signals found/).to_stderr
      end

      it "returns 0 exit code" do
        expect(described_class.run(["--dry-run"])).to eq(0)
      end
    end

    context "with changed Ruby files" do
      let(:test_file) { create_temp_ruby_file }

      before do
        allow(git_context).to receive(:changed_files).and_return([test_file])
      end

      after do
        File.delete(test_file) if File.exist?(test_file)
      end

      it "extracts signals from files" do
        output = capture_stdout { described_class.run(["--dry-run"]) }
        json = JSON.parse(output)

        expect(json["dashboard"]).to have_key("panels")
      end

      it "outputs valid JSON" do
        output = capture_stdout { described_class.run(["--dry-run"]) }

        expect { JSON.parse(output) }.not_to raise_error
      end
    end

    context "with metrics in changed files" do
      let(:metrics_file) { create_metrics_ruby_file }

      before do
        allow(git_context).to receive(:changed_files).and_return([metrics_file])
      end

      after do
        File.delete(metrics_file) if File.exist?(metrics_file)
      end

      it "outputs counter count to stderr" do
        expect { described_class.run(["--dry-run"]) }.to output(/2 counters/).to_stderr
      end

      it "outputs gauge count to stderr" do
        expect { described_class.run(["--dry-run"]) }.to output(/1 gauge/).to_stderr
      end

      it "outputs histogram count to stderr" do
        expect { described_class.run(["--dry-run"]) }.to output(/1 histogram/).to_stderr
      end

      it "outputs log count to stderr" do
        expect { described_class.run(["--dry-run"]) }.to output(/1 log/).to_stderr
      end

      it "outputs dry-run mode indicator" do
        expect { described_class.run(["--dry-run"]) }.to output(/Mode: dry-run/).to_stderr
      end

      it "outputs summary after JSON" do
        expect { described_class.run(["--dry-run"]) }.to output(/Dashboard created with 4 panels/).to_stderr
      end
    end

    context "with --verbose flag" do
      it "outputs progress to stderr" do
        expect { described_class.run(["--verbose", "--dry-run"]) }.to output(/Branch:/).to_stderr
      end
    end

    context "when limits exceeded" do
      let(:noisy_file) { create_noisy_ruby_file }

      before do
        allow(git_context).to receive(:changed_files).and_return([noisy_file])
      end

      after do
        File.delete(noisy_file) if File.exist?(noisy_file)
      end

      it "returns exit code 0 (dashboard still created)" do
        result = silence_stderr { described_class.run(["--dry-run"]) }
        expect(result).to eq(0)
      end

      it "outputs warning about excluded signals" do
        expect { described_class.run(["--dry-run"]) }.to output(/Some signals were excluded/i).to_stderr
      end
    end

    context "with --dry-run flag" do
      it "does not attempt to upload" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("GRAFANA_URL").and_return("https://grafana.example.com")
        allow(ENV).to receive(:[]).with("GRAFANA_TOKEN").and_return("token")

        expect(Diffdash::Clients::Grafana).not_to receive(:new)

        described_class.run(["--dry-run"])
      end
    end

    context "dashboard title sanitization" do
      let(:test_file) { create_temp_ruby_file }

      before do
        allow(git_context).to receive(:changed_files).and_return([test_file])
      end

      after do
        File.delete(test_file) if File.exist?(test_file)
      end

      it "removes special characters from branch name" do
        allow(git_context).to receive(:branch_name).and_return("feature/add-payments!")

        output = capture_stdout { described_class.run(["--dry-run"]) }
        json = JSON.parse(output)

        expect(json["dashboard"]["title"]).not_to include("/")
        expect(json["dashboard"]["title"]).not_to include("!")
      end

      it "truncates long branch names to 40 characters" do
        allow(git_context).to receive(:branch_name).and_return("a" * 50)

        output = capture_stdout { described_class.run(["--dry-run"]) }
        json = JSON.parse(output)

        expect(json["dashboard"]["title"].length).to be <= 40
      end

      it "uses pr-dashboard for empty sanitized name" do
        allow(git_context).to receive(:branch_name).and_return("!!!")

        output = capture_stdout { described_class.run(["--dry-run"]) }
        json = JSON.parse(output)

        expect(json["dashboard"]["title"]).to eq("pr-dashboard")
      end
    end
  end

  # Helper methods

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def silence_stderr
    original = $stderr
    $stderr = StringIO.new
    result = yield
    result
  ensure
    $stderr = original
  end

  def create_temp_ruby_file
    file = Tempfile.new(["test", ".rb"])
    file.write(<<~RUBY)
      class TestService
        def process
          logger.info "Processing"
        end
      end
    RUBY
    file.close
    file.path
  end

  def create_noisy_ruby_file
    file = Tempfile.new(["noisy", ".rb"])
    logs = 12.times.map { |i| "logger.info 'Log #{i}'" }.join("\n    ")
    file.write(<<~RUBY)
      class NoisyService
        def process
          #{logs}
        end
      end
    RUBY
    file.close
    file.path
  end

  def create_metrics_ruby_file
    file = Tempfile.new(["metrics", ".rb"])
    file.write(<<~RUBY)
      class MetricsService
        def process
          logger.info "Processing"
          StatsD.increment("payments.processed")
          StatsD.increment("payments.success")
          Prometheus.gauge(:queue_size).set(100)
          StatsD.timing("request.duration", 150)
        end
      end
    RUBY
    file.close
    file.path
  end
end
