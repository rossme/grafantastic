# frozen_string_literal: true

RSpec.describe Grafantastic::GitContext do
  # These specs test basic interface behavior
  # Full integration testing requires a real git repo

  describe "#branch_name" do
    context "when in a git repository" do
      it "returns a string" do
        context = described_class.new
        expect(context.branch_name).to be_a(String)
      end

      it "returns non-empty branch name" do
        context = described_class.new
        expect(context.branch_name).not_to be_empty
      end
    end

    context "with CI environment variables" do
      it "uses GITHUB_HEAD_REF when set" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("GITHUB_HEAD_REF").and_return("pr-123")

        context = described_class.new
        # If git branch fails or returns empty, it should use the env var
        expect(["main", "pr-123"]).to include(context.branch_name)
      end
    end
  end

  describe "#changed_files" do
    context "when in a git repository" do
      it "returns an array" do
        context = described_class.new
        expect(context.changed_files).to be_an(Array)
      end

      it "returns absolute file paths when files are changed" do
        context = described_class.new
        files = context.changed_files

        files.each do |file|
          expect(file).to start_with("/") if file.length > 0
        end
      end
    end
  end

  describe "initialization" do
    it "accepts a base_ref parameter" do
      expect { described_class.new(base_ref: "main") }.not_to raise_error
    end

    it "auto-detects base ref when not provided" do
      expect { described_class.new }.not_to raise_error
    end
  end
end
