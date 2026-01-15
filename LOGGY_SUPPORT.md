# Loggy Module Support

## Overview

Diffdash now supports the [Loggy](https://github.com/ddollar/loggy) gem's logging modules:
- `Loggy::ClassLogger`
- `Loggy::InstanceLogger`

When a class includes, prepends, or extends these modules, Diffdash will detect `log(...)` method calls and include them in generated Grafana dashboards.

## Supported Patterns

### Include Loggy::ClassLogger

```ruby
class PaymentProcessor
  include Loggy::ClassLogger
  
  def process_payment
    log(:info, "payment_started")
    log(:error, "payment_failed")
  end
end
```

### Include Loggy::InstanceLogger

```ruby
class OrderService
  include Loggy::InstanceLogger
  
  def create_order
    log(:info, "order_created")
    log(:warn, "order_validation_warning")
  end
end
```

### Extend for Class Methods

```ruby
class BatchProcessor
  extend Loggy::ClassLogger
  
  def self.process_batch
    log(:info, "batch_started")
    log(:info, "batch_completed")
  end
end
```

## Log Levels

All standard log levels are supported:

```ruby
log(:debug, "debug_message")
log(:info, "info_message")
log(:warn, "warning_message")
log(:error, "error_message")
log(:fatal, "fatal_message")
```

### Default Level

If no level is specified, `info` is used:

```ruby
log("task_completed")  # Equivalent to log(:info, "task_completed")
```

## Mixed Logging

Loggy and standard logger calls can coexist in the same class:

```ruby
class TransactionProcessor
  include Loggy::InstanceLogger
  
  def process_transaction
    log(:info, "transaction_started")      # Loggy style
    logger.info "Using standard logger"    # Standard style
    log(:info, "transaction_completed")    # Loggy style
  end
end
```

Both styles will be detected and included in the dashboard.

## Inheritance Support

Loggy modules work with Diffdash's inheritance tracking:

```ruby
# app/services/base_processor.rb
class BaseProcessor
  include Loggy::ClassLogger
  
  def log_start
    log(:info, "processing_started")
  end
end

# app/services/payment_processor.rb
class PaymentProcessor < BaseProcessor
  def charge
    log_start  # Inherited method with Loggy log call
    log(:info, "payment_charged")
  end
end
```

When `PaymentProcessor` is changed, signals from both the class and its parent `BaseProcessor` are extracted.

## How It Works

1. **Module Detection**: The AST visitor tracks `include`, `prepend`, and `extend` statements
2. **Context Awareness**: When processing a `log(...)` call, the visitor checks if the current class has included/prepended/extended a Loggy module
3. **Level Extraction**: The first argument is checked to see if it's a log level symbol; otherwise, `info` is used
4. **Event Name Extraction**: The message argument is processed the same way as standard logger calls

## Testing

Comprehensive test coverage includes:
- Detection of `log(...)` calls with Loggy modules
- All log levels (debug, info, warn, error, fatal)
- Default info level behavior
- Mixed Loggy and standard logger usage
- Include, prepend, and extend patterns
- Classes without Loggy modules (negative tests)
- Nested classes with Loggy modules

Run tests:

```bash
bundle exec rspec spec/diffdash/ast/visitor_spec.rb -fd | grep -A 10 "with Loggy"
bundle exec rspec spec/diffdash/integration/loggy_integration_spec.rb
```

## Grafana Compatibility

Loggy log calls are treated identically to standard logger calls in Grafana dashboards:
- Log panels use Loki as the data source
- Event names are extracted from log messages
- Log levels are preserved in metadata
- All standard Grafana log visualization features apply

## Example Output

When Diffdash processes a file with Loggy logs:

```
[diffdash] Dashboard created with 3 panels: 3 logs
[diffdash] Uploaded to: https://myorg.grafana.net/d/abc123/feature-branch
```

The dashboard will include log panels for each detected `log(...)` call, just like standard logger calls.
