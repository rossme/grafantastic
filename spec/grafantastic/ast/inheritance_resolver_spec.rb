# frozen_string_literal: true

RSpec.describe Grafantastic::AST::InheritanceResolver do
  subject(:resolver) { described_class.new }

  describe "#resolve_parent" do
    it "returns nil for nil parent class" do
      result = resolver.resolve_parent(nil, "/app/models/user.rb")
      expect(result).to be_nil
    end

    it "caches resolved paths" do
      allow(Dir).to receive(:glob).and_return([])
      allow(resolver).to receive(:`).and_return("")

      resolver.resolve_parent("BaseClass", "/app/models/user.rb")
      resolver.resolve_parent("BaseClass", "/app/models/other.rb")

      # Should only call glob patterns once due to caching
      expect(Dir).to have_received(:glob).at_most(4).times
    end

    context "with convention-based resolution" do
      it "converts CamelCase to snake_case" do
        allow(Dir).to receive(:glob).and_return([])
        allow(File).to receive(:dirname).and_return("/app/models")

        resolver.resolve_parent("PaymentProcessor", "/app/models/user.rb")

        expect(Dir).to have_received(:glob).with("/app/models/payment_processor.rb")
      end

      it "handles namespaced classes" do
        allow(Dir).to receive(:glob).and_return([])
        allow(File).to receive(:dirname).and_return("/app/models")

        resolver.resolve_parent("Services::PaymentProcessor", "/app/models/user.rb")

        expect(Dir).to have_received(:glob).with("/app/models/services/payment_processor.rb")
      end

      it "returns first matching file" do
        allow(Dir).to receive(:glob)
          .with("/app/services/base_processor.rb")
          .and_return(["/app/services/base_processor.rb"])
        allow(File).to receive(:dirname).and_return("/app/services")

        result = resolver.resolve_parent("BaseProcessor", "/app/services/payment.rb")

        expect(result).to eq("/app/services/base_processor.rb")
      end

      it "excludes spec files from matches" do
        allow(Dir).to receive(:glob).and_return([
          "/spec/support/base_processor.rb",
          "/app/services/base_processor.rb"
        ])
        allow(File).to receive(:dirname).and_return("/app/services")

        result = resolver.resolve_parent("BaseProcessor", "/app/services/payment.rb")

        expect(result).to eq("/app/services/base_processor.rb")
      end

      it "excludes test files from matches" do
        allow(Dir).to receive(:glob).and_return([
          "/app/services/base_processor_test.rb",
          "/app/services/base_processor.rb"
        ])
        allow(File).to receive(:dirname).and_return("/app/services")

        result = resolver.resolve_parent("BaseProcessor", "/app/services/payment.rb")

        expect(result).to eq("/app/services/base_processor.rb")
      end
    end
  end
end
