# frozen_string_literal: true

require "set"
require "fileutils"
require "tmpdir"

RSpec.describe Grafantastic::AST::AncestorResolver do
  subject(:resolver) { described_class.new }

  describe "#resolve" do
    it "returns nil for nil name" do
      result = resolver.resolve(nil, "/app/models/user.rb")
      expect(result).to be_nil
    end

    it "caches resolved paths" do
      allow(Dir).to receive(:glob).and_return([])
      allow(resolver).to receive(:`).and_return("")

      resolver.resolve("BaseClass", "/app/models/user.rb")
      resolver.resolve("BaseClass", "/app/models/other.rb")

      # Should only call glob patterns once due to caching
      expect(Dir).to have_received(:glob).at_most(6).times
    end

    context "with convention-based resolution" do
      it "converts CamelCase to snake_case" do
        allow(Dir).to receive(:glob).and_return([])
        allow(File).to receive(:dirname).and_return("/app/models")

        resolver.resolve("PaymentProcessor", "/app/models/user.rb")

        expect(Dir).to have_received(:glob).with("/app/models/payment_processor.rb")
      end

      it "handles namespaced classes" do
        allow(Dir).to receive(:glob).and_return([])
        allow(File).to receive(:dirname).and_return("/app/models")

        resolver.resolve("Services::PaymentProcessor", "/app/models/user.rb")

        expect(Dir).to have_received(:glob).with("/app/models/services/payment_processor.rb")
      end

      it "searches concerns directory for modules" do
        allow(Dir).to receive(:glob).and_return([])
        allow(File).to receive(:dirname).and_return("/app/models")

        resolver.resolve("Trackable", "/app/models/user.rb")

        expect(Dir).to have_received(:glob).with("/app/models/concerns/trackable.rb")
      end

      it "returns first matching file" do
        allow(Dir).to receive(:glob)
          .with("/app/services/base_processor.rb")
          .and_return(["/app/services/base_processor.rb"])
        allow(File).to receive(:dirname).and_return("/app/services")

        result = resolver.resolve("BaseProcessor", "/app/services/payment.rb")

        expect(result).to eq("/app/services/base_processor.rb")
      end

      it "excludes spec files from matches" do
        allow(Dir).to receive(:glob).and_return([
          "/spec/support/base_processor.rb",
          "/app/services/base_processor.rb"
        ])
        allow(File).to receive(:dirname).and_return("/app/services")

        result = resolver.resolve("BaseProcessor", "/app/services/payment.rb")

        expect(result).to eq("/app/services/base_processor.rb")
      end

      it "excludes test files from matches" do
        allow(Dir).to receive(:glob).and_return([
          "/app/services/base_processor_test.rb",
          "/app/services/base_processor.rb"
        ])
        allow(File).to receive(:dirname).and_return("/app/services")

        result = resolver.resolve("BaseProcessor", "/app/services/payment.rb")

        expect(result).to eq("/app/services/base_processor.rb")
      end
    end
  end

  describe "#resolve_parent" do
    it "is aliased to #resolve" do
      expect(resolver.method(:resolve_parent)).to eq(resolver.method(:resolve))
    end
  end

  describe "#collect_ancestors" do
    let(:temp_dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(temp_dir) }

    def write_file(name, content)
      path = File.join(temp_dir, name)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      path
    end

    it "collects parent class" do
      base_file = write_file("base_processor.rb", <<~RUBY)
        class BaseProcessor
          def log_base
            logger.info "base_action"
          end
        end
      RUBY

      child_source = <<~RUBY
        class ChildProcessor < BaseProcessor
          def process
            logger.info "child_action"
          end
        end
      RUBY

      child_file = write_file("child_processor.rb", child_source)
      ast = Grafantastic::AST::Parser.parse(child_source, child_file)
      visitor = Grafantastic::AST::Visitor.new(file_path: child_file, inheritance_depth: 0)
      visitor.process(ast)

      allow(resolver).to receive(:resolve).with("BaseProcessor", child_file).and_return(base_file)

      ancestors = resolver.collect_ancestors(visitor, child_file)

      expect(ancestors.size).to eq(1)
      expect(ancestors.first[:name]).to eq("BaseProcessor")
      expect(ancestors.first[:type]).to eq(:class)
      expect(ancestors.first[:depth]).to eq(1)
    end

    it "collects included modules" do
      module_file = write_file("loggable.rb", <<~RUBY)
        module Loggable
          def log_action
            logger.info "loggable_action"
          end
        end
      RUBY

      class_source = <<~RUBY
        class PaymentProcessor
          include Loggable
        end
      RUBY

      class_file = write_file("payment_processor.rb", class_source)
      ast = Grafantastic::AST::Parser.parse(class_source, class_file)
      visitor = Grafantastic::AST::Visitor.new(file_path: class_file, inheritance_depth: 0)
      visitor.process(ast)

      allow(resolver).to receive(:resolve).with("Loggable", class_file).and_return(module_file)

      ancestors = resolver.collect_ancestors(visitor, class_file)

      expect(ancestors.size).to eq(1)
      expect(ancestors.first[:name]).to eq("Loggable")
      expect(ancestors.first[:type]).to eq(:module)
    end

    it "collects prepended modules" do
      module_file = write_file("retryable.rb", <<~RUBY)
        module Retryable
          def with_retry
            logger.info "retrying"
          end
        end
      RUBY

      class_source = <<~RUBY
        class PaymentProcessor
          prepend Retryable
        end
      RUBY

      class_file = write_file("payment_processor.rb", class_source)
      ast = Grafantastic::AST::Parser.parse(class_source, class_file)
      visitor = Grafantastic::AST::Visitor.new(file_path: class_file, inheritance_depth: 0)
      visitor.process(ast)

      allow(resolver).to receive(:resolve).with("Retryable", class_file).and_return(module_file)

      ancestors = resolver.collect_ancestors(visitor, class_file)

      expect(ancestors.size).to eq(1)
      expect(ancestors.first[:name]).to eq("Retryable")
      expect(ancestors.first[:type]).to eq(:module)
    end

    it "collects multi-level inheritance" do
      grandparent_file = write_file("grandparent.rb", <<~RUBY)
        class GrandParent
          def grandparent_action
            logger.info "grandparent"
          end
        end
      RUBY

      parent_file = write_file("parent.rb", <<~RUBY)
        class Parent < GrandParent
          def parent_action
            logger.info "parent"
          end
        end
      RUBY

      child_source = <<~RUBY
        class Child < Parent
          def child_action
            logger.info "child"
          end
        end
      RUBY

      child_file = write_file("child.rb", child_source)
      ast = Grafantastic::AST::Parser.parse(child_source, child_file)
      visitor = Grafantastic::AST::Visitor.new(file_path: child_file, inheritance_depth: 0)
      visitor.process(ast)

      allow(resolver).to receive(:resolve).with("Parent", child_file).and_return(parent_file)
      allow(resolver).to receive(:resolve).with("GrandParent", parent_file).and_return(grandparent_file)

      ancestors = resolver.collect_ancestors(visitor, child_file)

      names = ancestors.map { |a| a[:name] }
      expect(names).to include("Parent", "GrandParent")

      parent_ancestor = ancestors.find { |a| a[:name] == "Parent" }
      grandparent_ancestor = ancestors.find { |a| a[:name] == "GrandParent" }
      expect(parent_ancestor[:depth]).to eq(1)
      expect(grandparent_ancestor[:depth]).to eq(2)
    end

    it "collects both parent and included modules" do
      base_file = write_file("base.rb", "class Base; end")
      module_file = write_file("loggable.rb", "module Loggable; end")

      class_source = <<~RUBY
        class Child < Base
          include Loggable
        end
      RUBY

      class_file = write_file("child.rb", class_source)
      ast = Grafantastic::AST::Parser.parse(class_source, class_file)
      visitor = Grafantastic::AST::Visitor.new(file_path: class_file, inheritance_depth: 0)
      visitor.process(ast)

      allow(resolver).to receive(:resolve).with("Base", class_file).and_return(base_file)
      allow(resolver).to receive(:resolve).with("Loggable", class_file).and_return(module_file)

      ancestors = resolver.collect_ancestors(visitor, class_file)

      names = ancestors.map { |a| a[:name] }
      expect(names).to contain_exactly("Base", "Loggable")
    end

    it "collects modules that include other modules" do
      base_module_file = write_file("base_loggable.rb", <<~RUBY)
        module BaseLoggable
          def base_log
            logger.info "base_loggable"
          end
        end
      RUBY

      loggable_file = write_file("loggable.rb", <<~RUBY)
        module Loggable
          include BaseLoggable

          def log_action
            logger.info "loggable"
          end
        end
      RUBY

      class_source = <<~RUBY
        class PaymentProcessor
          include Loggable
        end
      RUBY

      class_file = write_file("payment_processor.rb", class_source)
      ast = Grafantastic::AST::Parser.parse(class_source, class_file)
      visitor = Grafantastic::AST::Visitor.new(file_path: class_file, inheritance_depth: 0)
      visitor.process(ast)

      allow(resolver).to receive(:resolve).with("Loggable", class_file).and_return(loggable_file)
      allow(resolver).to receive(:resolve).with("BaseLoggable", loggable_file).and_return(base_module_file)

      ancestors = resolver.collect_ancestors(visitor, class_file)

      names = ancestors.map { |a| a[:name] }
      expect(names).to include("Loggable", "BaseLoggable")
    end

    it "respects MAX_DEPTH limit" do
      # Create a chain deeper than MAX_DEPTH (5)
      files = {}
      (1..7).each do |i|
        parent = i == 7 ? nil : "Class#{i + 1}"
        content = parent ? "class Class#{i} < #{parent}; end" : "class Class#{i}; end"
        files["Class#{i}"] = write_file("class#{i}.rb", content)
      end

      class_source = "class Class0 < Class1; end"
      class_file = write_file("class0.rb", class_source)
      ast = Grafantastic::AST::Parser.parse(class_source, class_file)
      visitor = Grafantastic::AST::Visitor.new(file_path: class_file, inheritance_depth: 0)
      visitor.process(ast)

      allow(resolver).to receive(:resolve).with("Class1", anything).and_return(files["Class1"])
      (2..7).each do |i|
        allow(resolver).to receive(:resolve).with("Class#{i}", anything).and_return(files["Class#{i}"])
      end

      ancestors = resolver.collect_ancestors(visitor, class_file)

      # Should stop at MAX_DEPTH (5), not go all the way to 7
      expect(ancestors.map { |a| a[:depth] }.max).to be <= 5
    end

    it "avoids infinite loops with circular includes" do
      module_a_file = write_file("module_a.rb", <<~RUBY)
        module ModuleA
          include ModuleB
        end
      RUBY

      module_b_file = write_file("module_b.rb", <<~RUBY)
        module ModuleB
          include ModuleA
        end
      RUBY

      class_source = <<~RUBY
        class MyClass
          include ModuleA
        end
      RUBY

      class_file = write_file("my_class.rb", class_source)
      ast = Grafantastic::AST::Parser.parse(class_source, class_file)
      visitor = Grafantastic::AST::Visitor.new(file_path: class_file, inheritance_depth: 0)
      visitor.process(ast)

      allow(resolver).to receive(:resolve).with("ModuleA", anything).and_return(module_a_file)
      allow(resolver).to receive(:resolve).with("ModuleB", anything).and_return(module_b_file)

      # Should not raise or infinite loop
      ancestors = resolver.collect_ancestors(visitor, class_file)

      names = ancestors.map { |a| a[:name] }
      expect(names).to include("ModuleA", "ModuleB")
      # Each should only appear once
      expect(names.count("ModuleA")).to eq(1)
      expect(names.count("ModuleB")).to eq(1)
    end

    it "returns empty array when no ancestors found" do
      class_source = "class Standalone; end"
      class_file = write_file("standalone.rb", class_source)
      ast = Grafantastic::AST::Parser.parse(class_source, class_file)
      visitor = Grafantastic::AST::Visitor.new(file_path: class_file, inheritance_depth: 0)
      visitor.process(ast)

      ancestors = resolver.collect_ancestors(visitor, class_file)

      expect(ancestors).to eq([])
    end

    it "handles unresolvable ancestors gracefully" do
      class_source = <<~RUBY
        class Child < UnknownParent
          include UnknownModule
        end
      RUBY

      class_file = write_file("child.rb", class_source)
      ast = Grafantastic::AST::Parser.parse(class_source, class_file)
      visitor = Grafantastic::AST::Visitor.new(file_path: class_file, inheritance_depth: 0)
      visitor.process(ast)

      allow(resolver).to receive(:resolve).and_return(nil)

      ancestors = resolver.collect_ancestors(visitor, class_file)

      expect(ancestors).to eq([])
    end
  end
end
