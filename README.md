# Grafantastic

PR-scoped observability signal extractor and Grafana dashboard generator.

## Overview

Grafantastic statically analyzes Ruby source code changed in a Pull Request and generates a Grafana dashboard JSON containing panels relevant to the observability signals found in that code.

## Installation

```bash
gem install grafantastic
```

Or from source:

```bash
gem build grafantastic.gemspec
gem install grafantastic-*.gem
```

## Quick Start

### 1. Create a `.env` file

```bash
GRAFANA_URL=https://myorg.grafana.net
GRAFANA_TOKEN=glsa_xxxxxxxxxxxx
GRAFANA_FOLDER_ID=42  # optional
```

### 2. Find your folder ID (optional)

```bash
grafantastic folders
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
grafantastic

# Or dry-run to see JSON without uploading
grafantastic --dry-run
```

## CLI Usage

```bash
grafantastic [command] [options]
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
| `GRAFANTASTIC_DRY_RUN` | No | Set to `true` to force dry-run mode |

## Output

When signals are found:

```
[grafantastic] v0.3.0
[grafantastic] Found: 2 logs, 3 counters, 1 gauge, 1 histogram
[grafantastic] Creating dashboard JSON with 4 panels
[grafantastic] Please see: 1 dynamic metric could not be added
```

**If no signals are found, no dashboard is created:**

```
[grafantastic] v0.3.0
[grafantastic] No observability signals found in changed files
[grafantastic] Dashboard not created
```

## Observability Signals

### Logs

- `logger.info`, `logger.debug`, `logger.warn`, `logger.error`, `logger.fatal`
- `Rails.logger.*`
- `@logger.*`

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

      - name: Install grafantastic
        run: gem install grafantastic

      - name: Generate dashboard
        env:
          GRAFANA_URL: ${{ secrets.GRAFANA_URL }}
          GRAFANA_TOKEN: ${{ secrets.GRAFANA_TOKEN }}
          GRAFANA_FOLDER_ID: ${{ secrets.GRAFANA_FOLDER_ID }}
        run: grafantastic --verbose
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
gem build grafantastic.gemspec
```

## License

MIT
