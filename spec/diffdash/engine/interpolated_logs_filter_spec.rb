# frozen_string_literal: true

RSpec.describe Diffdash::Engine::Engine do
  let(:temp_dir) { Dir.mktmpdir }
  let(:ruby_file) { File.join(temp_dir, "app.rb") }

  before do
    # Create a Ruby file with both interpolated and structured logs
    File.write(ruby_file, <<~RUBY)
      class MyService
        def process(user)
          Rails.logger.info("Starting process")           # structured
          Rails.logger.info("Processing user \#{user.id}") # interpolated
          Rails.logger.warn("process_complete")           # structured
        end
      end
    RUBY
  end

  after do
    FileUtils.remove_entry(temp_dir)
  end

  def create_config(interpolated_setting)
    config = instance_double(Diffdash::Config)
    allow(config).to receive(:max_logs).and_return(10)
    allow(config).to receive(:max_metrics).and_return(10)
    allow(config).to receive(:max_events).and_return(5)
    allow(config).to receive(:max_panels).and_return(12)
    allow(config).to receive(:interpolated_logs).and_return(interpolated_setting)
    config
  end

  def create_change_set
    change_set = instance_double(Diffdash::Engine::ChangeSet)
    allow(change_set).to receive(:filtered_files).and_return([ruby_file])
    allow(change_set).to receive(:to_h).and_return({ files: [ruby_file] })
    change_set
  end

  describe "interpolated_logs filtering" do
    context "when interpolated_logs is :include (default)" do
      it "includes all logs in the bundle" do
        config = create_config(:include)
        engine = described_class.new(config: config)
        bundle = engine.run(change_set: create_change_set)

        expect(bundle.logs.size).to eq(3)
        expect(engine.excluded_interpolated_count).to eq(0)
      end
    end

    context "when interpolated_logs is :exclude" do
      it "excludes interpolated logs from the bundle" do
        config = create_config(:exclude)
        engine = described_class.new(config: config)
        bundle = engine.run(change_set: create_change_set)

        # Only 2 structured logs should remain
        expect(bundle.logs.size).to eq(2)
        expect(engine.excluded_interpolated_count).to eq(1)

        log_names = bundle.logs.map(&:name)
        expect(log_names).to include("Starting process")
        expect(log_names).to include("process_complete")
        expect(log_names).not_to include(match(/Processing user/))
      end

      it "tracks excluded count in metadata" do
        config = create_config(:exclude)
        engine = described_class.new(config: config)
        bundle = engine.run(change_set: create_change_set)

        expect(bundle.metadata[:excluded_interpolated_count]).to eq(1)
      end
    end

    context "when interpolated_logs is :warn" do
      it "includes all logs (warn only affects CLI output)" do
        config = create_config(:warn)
        engine = described_class.new(config: config)
        bundle = engine.run(change_set: create_change_set)

        expect(bundle.logs.size).to eq(3)
        expect(engine.excluded_interpolated_count).to eq(0)
      end
    end
  end
end
