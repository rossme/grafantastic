# Example demonstrating Loggy::ClassLogger and Loggy::InstanceLogger support

# Example 1: Using Loggy::ClassLogger
class PaymentProcessor
  include Loggy::ClassLogger
  
  def process_payment(amount)
    log(:info, "payment_started")
    
    # Process payment logic here
    
    if amount > 0
      log(:info, "payment_processed_successfully")
    else
      log(:error, "invalid_payment_amount")
    end
  end
end

# Example 2: Using Loggy::InstanceLogger
class OrderProcessor
  include Loggy::InstanceLogger
  
  def process_order(order_id)
    log(:info, "order_processing_started")
    
    # Order processing logic
    
    log(:info, "order_completed")
  rescue StandardError => e
    log(:error, "order_processing_failed")
    raise
  end
end

# Example 3: Using extend with Loggy::ClassLogger for class methods
class BatchProcessor
  extend Loggy::ClassLogger
  
  def self.process_batch(batch_size)
    log(:info, "batch_processing_started")
    
    # Batch processing logic
    
    log(:info, "batch_completed")
  end
end

# Example 4: Mixed logging approaches (Loggy + standard logger)
class TransactionProcessor
  include Loggy::InstanceLogger
  
  def process_transaction(txn_id)
    # Using Loggy's log method
    log(:info, "transaction_started")
    
    # Can also use standard logger.info if needed
    logger.info "Standard logger message"
    
    log(:info, "transaction_completed")
  end
end

# Example 5: Different log levels
class ErrorHandler
  include Loggy::ClassLogger
  
  def handle_request
    log(:debug, "request_received")
    log(:info, "request_processing")
    log(:warn, "potential_issue_detected")
    log(:error, "request_failed")
    log(:fatal, "critical_system_error")
  end
end
