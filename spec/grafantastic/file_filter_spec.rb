# frozen_string_literal: true

RSpec.describe Grafantastic::FileFilter do
  describe ".filter" do
    it "includes regular Ruby files" do
      files = ["/app/models/user.rb", "/app/services/payment.rb"]
      expect(described_class.filter(files)).to eq(files)
    end

    it "excludes _spec.rb files" do
      files = ["/app/models/user.rb", "/spec/models/user_spec.rb"]
      expect(described_class.filter(files)).to eq(["/app/models/user.rb"])
    end

    it "excludes _test.rb files" do
      files = ["/app/models/user.rb", "/test/models/user_test.rb"]
      expect(described_class.filter(files)).to eq(["/app/models/user.rb"])
    end

    it "excludes files in /spec/ directory" do
      files = ["/app/models/user.rb", "/spec/support/helpers.rb"]
      expect(described_class.filter(files)).to eq(["/app/models/user.rb"])
    end

    it "excludes files in /test/ directory" do
      files = ["/app/models/user.rb", "/test/fixtures/data.rb"]
      expect(described_class.filter(files)).to eq(["/app/models/user.rb"])
    end

    it "excludes files in /config/ directory" do
      files = ["/app/models/user.rb", "/config/initializers/sidekiq.rb"]
      expect(described_class.filter(files)).to eq(["/app/models/user.rb"])
    end

    it "excludes non-Ruby files" do
      files = ["/app/models/user.rb", "/README.md", "/config.yml", "/data.json"]
      expect(described_class.filter(files)).to eq(["/app/models/user.rb"])
    end

    it "returns empty array when all files are excluded" do
      files = ["/spec/models/user_spec.rb", "/test/models/user_test.rb"]
      expect(described_class.filter(files)).to eq([])
    end

    it "handles empty input" do
      expect(described_class.filter([])).to eq([])
    end
  end

  describe ".include_file?" do
    it "returns true for regular Ruby application files" do
      expect(described_class.include_file?("/app/models/user.rb")).to be true
      expect(described_class.include_file?("/lib/grafantastic/parser.rb")).to be true
    end

    it "returns false for spec files" do
      expect(described_class.include_file?("/spec/models/user_spec.rb")).to be false
    end

    it "returns false for test files" do
      expect(described_class.include_file?("/test/models/user_test.rb")).to be false
    end

    it "returns false for config files" do
      expect(described_class.include_file?("/config/application.rb")).to be false
    end

    it "returns false for non-Ruby files" do
      expect(described_class.include_file?("/README.md")).to be false
      expect(described_class.include_file?("/config.yml")).to be false
    end
  end
end
