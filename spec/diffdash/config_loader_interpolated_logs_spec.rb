# frozen_string_literal: true

RSpec.describe Diffdash::ConfigLoader do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(temp_dir)
  end

  def create_config_file(content)
    File.write(File.join(temp_dir, "diffdash.yml"), content)
  end

  describe "#interpolated_logs" do
    context "with no configuration" do
      it "defaults to :include" do
        loader = described_class.new(working_dir: temp_dir)
        expect(loader.interpolated_logs).to eq(:include)
      end
    end

    context "with YAML configuration" do
      it "returns :exclude when configured" do
        create_config_file(<<~YAML)
          signals:
            interpolated_logs: exclude
        YAML
        loader = described_class.new(working_dir: temp_dir)
        expect(loader.interpolated_logs).to eq(:exclude)
      end

      it "returns :warn when configured" do
        create_config_file(<<~YAML)
          signals:
            interpolated_logs: warn
        YAML
        loader = described_class.new(working_dir: temp_dir)
        expect(loader.interpolated_logs).to eq(:warn)
      end

      it "returns :include when configured" do
        create_config_file(<<~YAML)
          signals:
            interpolated_logs: include
        YAML
        loader = described_class.new(working_dir: temp_dir)
        expect(loader.interpolated_logs).to eq(:include)
      end

      it "defaults to :include for invalid values" do
        create_config_file(<<~YAML)
          signals:
            interpolated_logs: invalid_value
        YAML
        loader = described_class.new(working_dir: temp_dir)
        expect(loader.interpolated_logs).to eq(:include)
      end
    end

    context "with environment variable" do
      before do
        allow(ENV).to receive(:[]).and_call_original
      end

      it "returns :exclude from env var" do
        allow(ENV).to receive(:[]).with("DIFFDASH_INTERPOLATED_LOGS").and_return("exclude")
        loader = described_class.new(working_dir: temp_dir)
        expect(loader.interpolated_logs).to eq(:exclude)
      end

      it "returns :warn from env var" do
        allow(ENV).to receive(:[]).with("DIFFDASH_INTERPOLATED_LOGS").and_return("warn")
        loader = described_class.new(working_dir: temp_dir)
        expect(loader.interpolated_logs).to eq(:warn)
      end

      it "env var overrides YAML config" do
        create_config_file(<<~YAML)
          signals:
            interpolated_logs: include
        YAML
        allow(ENV).to receive(:[]).with("DIFFDASH_INTERPOLATED_LOGS").and_return("exclude")
        loader = described_class.new(working_dir: temp_dir)
        expect(loader.interpolated_logs).to eq(:exclude)
      end

      it "defaults to :include for invalid env var" do
        allow(ENV).to receive(:[]).with("DIFFDASH_INTERPOLATED_LOGS").and_return("invalid")
        loader = described_class.new(working_dir: temp_dir)
        expect(loader.interpolated_logs).to eq(:include)
      end
    end
  end
end
