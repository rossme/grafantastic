# Ruby Logger Coverage

This document outlines diffdash's comprehensive support for Ruby's standard [Logger](https://ruby.github.io/logger/) library patterns.

## ✅ Fully Supported Ruby Logger Patterns

### 1. Standard Log Levels

All standard Ruby Logger severity levels are supported:

```ruby
logger.debug("debug message")    # DEBUG level
logger.info("info message")      # INFO level  
logger.warn("warning message")   # WARN level
logger.error("error message")    # ERROR level
logger.fatal("fatal message")    # FATAL level
logger.unknown("unknown message") # UNKNOWN level
```

**Test Coverage:** ✅ All levels tested

### 2. Generic Logging Methods

The generic `add` and `log` methods (which are aliases) with explicit severity:

```ruby
# With symbol severity
logger.add(:info, "message")
logger.log(:error, "message")

# With Logger constant severity  
logger.add(Logger::WARN, "message")
logger.add(Logger::INFO, "message")

# With numeric severity (0=debug, 1=info, 2=warn, 3=error, 4=fatal, 5=unknown)
logger.add(2, "message")  # WARN level
logger.add(3, "message")  # ERROR level
```

**Test Coverage:** ✅ Symbol, constant, and numeric severities tested

### 3. Logger Instance Patterns

Multiple ways to access logger instances:

```ruby
# Instance variables
@logger.info("message")
@@logger.info("message")  # Class variables

# Local variables
logger = Logger.new(STDOUT)
logger.info("message")

# Method calls
logger.info("message")
current_logger.debug("message")
```

**Test Coverage:** ✅ Instance, class, and local variables tested

### 4. Logger Constants

Common patterns using constants for logger instances:

```ruby
class MyClass
  LOG = Logger.new(STDOUT)
  LOGGER = Logger.new(STDERR)
  
  def process
    LOG.info("processing")
    LOGGER.error("failed")
  end
end
```

**Detection Pattern:** Matches constants containing `log` or `logger` (case-insensitive)

**Test Coverage:** ✅ LOG and LOGGER constants tested

### 5. Rails.logger

Rails' built-in logger is fully supported:

```ruby
Rails.logger.debug("debug in Rails")
Rails.logger.info("info in Rails")
Rails.logger.error("error in Rails")
```

**Test Coverage:** ✅ Rails.logger tested

### 6. Chained Logger Access

Logger accessed through method chains:

```ruby
# Object.logger pattern
user.logger.info("user action")
service.logger.error("service error")

# Rails.logger pattern  
Rails.logger.info("rails logging")
```

**Test Coverage:** ✅ Chained access tested

## Event Name Extraction

Diffdash extracts event names from log messages for dashboard organization:

### String Literals
```ruby
logger.info("payment_processed")  # Event: payment_processed
```

### Symbols
```ruby
logger.info(:order_completed)  # Event: order_completed
```

### Natural Language
```ruby
logger.info("Processing payment for user")  
# Event: processing_payment_for_user
```

### Interpolated Strings
```ruby
logger.info("Order #{id} processed")
# Event: order_processed (static parts only)
```

**Test Coverage:** ✅ All extraction patterns tested

## Not Supported (By Design)

These Ruby Logger features are intentionally not supported as they're not relevant for static analysis:

### Runtime-Only Features
- `logger.level = ...` (log level configuration)
- `logger.formatter = ...` (output formatting)
- `logger.datetime_format = ...` (timestamp formatting)
- `logger << "message"` (raw append operator)
- Predicate methods: `logger.debug?`, `logger.info?`
- Level-setting methods: `logger.debug!`, `logger.info!`
- `logger.close`, `logger.reopen` (lifecycle management)
- Block-based lazy evaluation: `logger.info { expensive_computation }`

These features don't emit observable signals that would appear in Grafana dashboards, so they're excluded from static analysis.

## Grafana Integration

All detected Ruby Logger calls are:
- Converted to Loki log panel queries
- Grouped by event name
- Labeled with severity level
- Associated with the defining class/module
- Included in PR-scoped Grafana dashboards

## Test Coverage Summary

- **Total Visitor Tests:** 46
- **Logger-Specific Tests:** 16
- **Coverage:** All standard Ruby Logger usage patterns
- **Test Files:**
  - `spec/diffdash/ast/visitor_spec.rb`
  - `spec/diffdash/signals/log_extractor_spec.rb`

## References

- [Ruby Logger Documentation](https://ruby.github.io/logger/)
- [Ruby Logger API Reference](https://docs.ruby-lang.org/en/3.4/Logger.html)
- [Logger Class Documentation](https://ruby-doc.org/current/stdlibs/logger/Logger.html)
