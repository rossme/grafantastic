# frozen_string_literal: true

RSpec.describe "Loggy integration" do
  let(:file_path) { "/app/services/payment_processor.rb" }
  
  it "detects log calls from Loggy modules through inheritance" do
    source = <<~RUBY
      class PaymentProcessor
        include Loggy::ClassLogger
        
        def process
          log(:info, "payment_started")
          log(:error, "payment_failed")
        end
      end
    RUBY
    
    ast = Diffdash::AST::Parser.parse(source, file_path)
    visitor = Diffdash::AST::Visitor.new(file_path: file_path, inheritance_depth: 0)
    visitor.process(ast)
    
    # Extract signals
    log_signals = Diffdash::Signals::LogExtractor.extract(visitor)
    
    expect(log_signals.size).to eq(2)
    expect(log_signals.map(&:name)).to include("payment_started", "payment_failed")
    expect(log_signals.map { |s| s.metadata[:level] }).to eq(%w[info error])
  end
  
  it "works with both Loggy and standard logger in the same class" do
    source = <<~RUBY
      class OrderProcessor
        include Loggy::InstanceLogger
        
        def process_order
          log(:info, "order_started")
          logger.info "standard_log_message"
          log(:info, "order_completed")
        end
      end
    RUBY
    
    ast = Diffdash::AST::Parser.parse(source, file_path)
    visitor = Diffdash::AST::Visitor.new(file_path: file_path, inheritance_depth: 0)
    visitor.process(ast)
    
    log_signals = Diffdash::Signals::LogExtractor.extract(visitor)
    
    expect(log_signals.size).to eq(3)
    event_names = log_signals.map(&:name)
    expect(event_names).to include("order_started", "standard_log_message", "order_completed")
  end
  
  it "does not detect log calls without Loggy modules" do
    source = <<~RUBY
      class RegularClass
        def process
          log(:info, "this should not be detected")
        end
      end
    RUBY
    
    ast = Diffdash::AST::Parser.parse(source, file_path)
    visitor = Diffdash::AST::Visitor.new(file_path: file_path, inheritance_depth: 0)
    visitor.process(ast)
    
    log_signals = Diffdash::Signals::LogExtractor.extract(visitor)
    
    expect(log_signals).to be_empty
  end
  
  it "handles default info level for Loggy log calls" do
    source = <<~RUBY
      class TaskProcessor
        include Loggy::ClassLogger
        
        def run
          log("task_completed")
        end
      end
    RUBY
    
    ast = Diffdash::AST::Parser.parse(source, file_path)
    visitor = Diffdash::AST::Visitor.new(file_path: file_path, inheritance_depth: 0)
    visitor.process(ast)
    
    log_signals = Diffdash::Signals::LogExtractor.extract(visitor)
    
    expect(log_signals.size).to eq(1)
    expect(log_signals.first.metadata[:level]).to eq("info")
    expect(log_signals.first.name).to eq("task_completed")
  end
  
  it "supports extend for class-level Loggy usage" do
    source = <<~RUBY
      class BatchProcessor
        extend Loggy::ClassLogger
        
        def self.process_batch
          log(:warn, "batch_started")
        end
      end
    RUBY
    
    ast = Diffdash::AST::Parser.parse(source, file_path)
    visitor = Diffdash::AST::Visitor.new(file_path: file_path, inheritance_depth: 0)
    visitor.process(ast)
    
    log_signals = Diffdash::Signals::LogExtractor.extract(visitor)
    
    expect(log_signals.size).to eq(1)
    expect(log_signals.first.metadata[:level]).to eq("warn")
  end
end
