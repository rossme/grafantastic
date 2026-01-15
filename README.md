# Diffdash

PR-scoped observability signal extractor and Grafana dashboard generator.

## Overview

Diffdash statically analyzes Ruby source code changed in a Pull Request and generates a Grafana dashboard JSON containing panels relevant to the observability signals found in that code.

## Installation

```bash
gem install diffdash
```

Or from source:

```bash
gem build diffdash.gemspec
gem install diffdash-*.gem
```

## Quick Start

### 1. Add these to your application's `.env` (dotenv) file

```bash
GRAFANA_URL=https://myorg.grafana.net
GRAFANA_TOKEN=glsa_xxxxxxxxxxxx
GRAFANA_FOLDER_ID=42  # optional
```

### 2. Find your folder ID (optional)

```bash
diffdash folders
```

Output:
```
Available Grafana folders:

  ID: 1      Title: General
  ID: 42     Title: PR Dashboards
  ID: 103    Title: Production

Set GRAFANA_FOLDER_ID in your .env file to use a specific folder
```

### 3. Generate Dashboard

```bash
# From your repo with changed files
diffdash

# Or dry-run to see JSON without uploading
diffdash --dry-run
```

## CLI Usage

```bash
diffdash [command] [options]
```

**Commands:**
- `folders` - List available Grafana folders
- *(none)* - Run analysis and generate/upload dashboard

**Options:**
- `--dry-run` - Generate JSON only, don't upload to Grafana
- `--verbose` - Show detailed progress and dynamic metric warnings
- `--help` - Show help

## Environment Variables

Set these in a `.env` file in your project root:

| Variable | Required | Description |
|----------|----------|-------------|
| `GRAFANA_URL` | Yes | Grafana instance URL (e.g., `https://myorg.grafana.net`) |
| `GRAFANA_TOKEN` | Yes | Grafana API token (Service Account token with Editor role) |
| `GRAFANA_FOLDER_ID` | No | Target folder ID for dashboards |
| `DIFFDASH_DRY_RUN` | No | Set to `true` to force dry-run mode |

## Output

When signals are found, JSON is output first, then a summary:

```
[diffdash] v0.4.0
{ ... dashboard JSON ... }

[diffdash] Dashboard created with 4 panels: 2 logs, 3 counters, 1 gauge, 1 histogram
[diffdash] Uploaded to: https://myorg.grafana.net/d/abc123/feature-branch
[diffdash] Note: 1 dynamic metric could not be added
```

In dry-run mode:

```
[diffdash] v0.4.0
{ ... dashboard JSON ... }

[diffdash] Dashboard created with 4 panels: 2 logs, 3 counters, 1 gauge, 1 histogram
[diffdash] Mode: dry-run (not uploaded)
```

**If no signals are found, no dashboard is created:**

```
[diffdash] v0.4.0
[diffdash] No observability signals found in changed files
[diffdash] Dashboard not created
```

## Observability Signals

### Logs

- `logger.info`, `logger.debug`, `logger.warn`, `logger.error`, `logger.fatal`
- `Rails.logger.*`
- `@logger.*`
- `log(...)` in classes that include/extend `Loggy::ClassLogger` or `Loggy::InstanceLogger`

### Metrics

| Client | Methods | Metric Type |
|--------|---------|-------------|
| Prometheus | `counter().increment` | counter |
| Prometheus | `gauge().set` | gauge |
| Prometheus | `histogram().observe` | histogram |
| Prometheus | `summary()` | summary |
| StatsD | `increment`, `incr` | counter |
| StatsD | `gauge`, `set` | gauge |
| StatsD | `timing`, `time` | histogram |
| Statsd | (same as StatsD) | |
| Hesiod | `emit` | counter |

### Dynamic Metrics Warning

Metrics with runtime-determined names cannot be added to dashboards:

```ruby
# ❌ Dynamic - cannot be analyzed statically
Prometheus.counter(entity.id).increment

# ✅ Static - will be detected and added to dashboard
Prometheus.counter(:records_processed).increment(labels: { entity_id: id })
```

Use `--verbose` to see details about dynamic metrics that were detected but couldn't be added.

## Guard Rails

Hard limits prevent noisy dashboards:

| Signal Type | Max Count |
|-------------|-----------|
| Logs | 10 |
| Metrics | 10 |
| Events | 5 |
| Total Panels | 12 |

If any limit is exceeded, the gem aborts with a clear error message and exits with code 1.

## File Filtering

**Included:**
- Files ending with `.rb`
- Ruby application code

**Excluded:**
- `*_spec.rb`, `*_test.rb`
- Files in `/spec/`, `/test/`, `/config/`
- Non-Ruby files

## Inheritance & Module Support

Signals are extracted from:
- The touched class/module (depth = 0)
- Parent classes (multi-level inheritance up to 5 levels deep)
- Included modules (`include`)
- Prepended modules (`prepend`)

### Example

```ruby
module Loggable
  def log_action
    logger.info "action_performed"  # ✅ Detected
  end
end

class BaseProcessor
  def process
    StatsD.increment("base.processed")  # ✅ Detected
  end
end

class PaymentProcessor < BaseProcessor
  include Loggable
  
  def charge
    StatsD.increment("payment.charged")  # ✅ Detected
  end
end
```

When `PaymentProcessor` is changed, signals from `BaseProcessor` and `Loggable` are also extracted.

### Loggy Module Support

Diffdash supports the [Loggy](https://github.com/ddollar/loggy) gem's `ClassLogger` and `InstanceLogger` modules:

```ruby
class PaymentProcessor
  include Loggy::ClassLogger
  
  def process_payment
    log(:info, "payment_started")
    log(:error, "payment_failed") if error
    # Or with default info level:
    log("payment_completed")
  end
end

class OrderService
  include Loggy::InstanceLogger
  
  def create_order
    log(:info, "order_created")
  end
end

class BatchProcessor
  extend Loggy::ClassLogger
  
  def self.process_batch
    log(:warn, "batch_processing_started")
  end
end
```

The `log(...)` method calls are detected and included in dashboards when the class includes, prepends, or extends `Loggy::ClassLogger` or `Loggy::InstanceLogger`.

## Dashboard Behavior

- **Deterministic UID:** Dashboard UID is derived from the branch name, ensuring the same PR always updates the same dashboard
- **Overwrite:** Re-running the gem updates the existing dashboard rather than creating duplicates
- **Template Variables:** Dashboards include `$service`, `$env`, and `$datasource` variables

## GitHub Actions Integration

### Setup

1. **Add secrets to your repository:**
   - `GRAFANA_URL` - Your Grafana instance URL
   - `GRAFANA_TOKEN` - Service Account token with Editor role
   - `GRAFANA_FOLDER_ID` (optional) - Folder ID for dashboards

2. **Create workflow file** `.github/workflows/pr-dashboard.yml`:

```yaml
name: PR Observability Dashboard

on:
  pull_request:
    types: [opened, reopened, synchronize]

jobs:
  dashboard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.x'

      - name: Install diffdash
        run: gem install diffdash

      - name: Generate dashboard
        env:
          GRAFANA_URL: ${{ secrets.GRAFANA_URL }}
          GRAFANA_TOKEN: ${{ secrets.GRAFANA_TOKEN }}
          GRAFANA_FOLDER_ID: ${{ secrets.GRAFANA_FOLDER_ID }}
        run: diffdash --verbose
```

## Development

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop

# Build gem
gem build diffdash.gemspec
```

## License

MIT
