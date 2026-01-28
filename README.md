# Diffdash

This is the future of developer-centric observability. Not bigger dashboards, but smarter, smaller, more relevant ones.
PR-scoped observability signal extractor and Grafana dashboard generator.

Observability focused on the code _**you**_ are shipping.

## Overview

Diffdash statically analyzes Ruby source code changed in a Pull Request and generates a Grafana dashboard JSON containing panels relevant to the observability signals found in that code. No more searching through dashboards with thousands of metrics — see exactly the logs and metrics that matter to you.

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

### Option A: Configuration File (Recommended for Teams)

Create a `diffdash.yml` in your repository root:

```yaml
grafana:
  url: https://myorg.grafana.net
  folder_id: 42

ignore_paths:
  - vendor/
  - lib/legacy/

default_env: production
```

Then set your API token via environment variable (never commit tokens):

```bash
export DIFFDASH_GRAFANA_TOKEN=glsa_xxxxxxxxxxxx
```

### Option B: Environment Variables Only

Add to your `.env` file:

```bash
DIFFDASH_GRAFANA_URL=https://myorg.grafana.net
DIFFDASH_GRAFANA_TOKEN=glsa_xxxxxxxxxxxx
DIFFDASH_GRAFANA_FOLDER_ID=42  # optional
```

### Find Your Folder ID (Optional)

```bash
diffdash folders
```

Output:
```
Available Grafana folders:

  ID: 1      Title: General
  ID: 42     Title: PR Dashboards
  ID: 103    Title: Production

Set DIFFDASH_GRAFANA_FOLDER_ID in your .env file to use a specific folder
```

### Generate Dashboard

```bash
# From your repo with changed files
diffdash

# Or dry-run to see JSON without uploading
diffdash --dry-run

# Use a custom config file
diffdash --config path/to/config.yml
```

## CLI Usage

```bash
diffdash [command] [options]
```

**Commands:**
- `folders` - List available Grafana folders
- *(none)* - Run analysis and generate/upload dashboard

**Options:**
- `--config FILE` - Path to configuration file (default: `diffdash.yml` in repo root)
- `--dry-run` - Generate JSON only, don't upload to Grafana
- `--list-signals` - Show detected signals without generating dashboard (great for debugging)
- `--verbose` - Show detailed progress, config source, and dynamic metric warnings
- `--version` - Show version number
- `--help` - Show help

### Examples

```bash
# Generate and upload dashboard
diffdash

# See what signals would be detected (no upload)
diffdash --list-signals

# Generate JSON without uploading
diffdash --dry-run

# Use custom config file
diffdash --config path/to/config.yml

# Verbose output with detailed progress
diffdash --verbose
```

## Configuration File

Create a `diffdash.yml` (or `.diffdash.yml`) in your repository root to share configuration across your team.

### Example Configuration

```yaml
# Grafana connection
grafana:
  url: https://myorg.grafana.net
  folder_id: 42

# Output adapters (grafana, json)
outputs:
  - grafana
  - json

# General settings
default_env: production
pr_comment: true
app_name: my-service

# File filtering
ignore_paths:
  - vendor/
  - lib/legacy/
  - tmp/

include_paths:        # Optional whitelist (empty = scan all)
  - app/
  - lib/

excluded_suffixes:    # Defaults: _spec.rb, _test.rb
  - _spec.rb
  - _test.rb

excluded_directories: # Defaults: spec, test, config
  - spec
  - test
  - config
```

### Configuration Precedence

Configuration is loaded from multiple sources (highest to lowest priority):

1. **Environment variables** - Always take precedence
2. **`--config` flag** - Explicitly specified config file
3. **Config file in current directory** - `diffdash.yml`, `.diffdash.yml`, `diffdash.yaml`, `.diffdash.yaml`
4. **Config file in git root** - If different from current directory
5. **Default values**

### Security Note

**API tokens are only loaded from environment variables** — never from config files. This prevents accidental commits of secrets. The `grafana.token` key is intentionally ignored if present in the YAML.

## Environment Variables

Environment variables can be set in a `.env` file or exported directly. They **always override** config file values.

| Variable | Required | Config File Equivalent | Description |
|----------|----------|------------------------|-------------|
| `DIFFDASH_GRAFANA_URL` | Yes* | `grafana.url` | Grafana instance URL |
| `DIFFDASH_GRAFANA_TOKEN` | Yes | *(env only)* | Grafana API token (never in config file) |
| `DIFFDASH_GRAFANA_FOLDER_ID` | No | `grafana.folder_id` | Target folder ID for dashboards |
| `DIFFDASH_OUTPUTS` | No | `outputs` | Comma-separated outputs (default: `grafana`) |
| `DIFFDASH_DRY_RUN` | No | — | Set to `true` to force dry-run mode |
| `DIFFDASH_DEFAULT_ENV` | No | `default_env` | Default environment filter (default: `production`) |
| `DIFFDASH_APP_NAME` | No | `app_name` | Override app name (defaults to Git repo name) |
| `DIFFDASH_PR_COMMENT` | No | `pr_comment` | Set to `false` to disable PR comments |
| `DIFFDASH_PR_DEPLOY_ANNOTATION_EXPR` | No | `pr_deploy_annotation_expr` | PromQL expr for PR deployment annotation |

*Required unless set in config file.

**Legacy fallbacks:** `GRAFANA_URL`, `GRAFANA_TOKEN`, `GRAFANA_FOLDER_ID` are also supported if the `DIFFDASH_` versions aren't set.

## Output

### Normal Mode (Upload to Grafana)

When signals are found, JSON is output first, then a summary:

```
[diffdash] vX.X.X
{ ... dashboard JSON ... }

[diffdash] Dashboard created with 4 panels: 2 logs, 3 counters, 1 gauge, 1 histogram
[diffdash] Uploaded to: https://myorg.grafana.net/d/abc123/feature-branch
[diffdash] Note: 1 dynamic metric could not be added
```

### Dry-Run Mode

```
[diffdash] vX.X.X
{ ... dashboard JSON ... }

[diffdash] Dashboard created with 4 panels: 2 logs, 3 counters, 1 gauge, 1 histogram
[diffdash] Mode: dry-run (not uploaded)
```

### List Signals Mode

Quick overview without generating a dashboard:

```
[diffdash] vX.X.X
[diffdash] Branch: feature-payments
[diffdash] Changed files: 3
[diffdash] Filtered Ruby files: 2

📊 Detected Signals

Logs (5):
  PaymentProcessor:
    • "payment_started" (info)
    • "payment_completed" (info)
    • "payment_failed" (error)
  UsersController:
    • "user_created" (info)
    • "user_updated" (info)

Metrics (4):
  Counters (3):
    • payments.processed
    • payments.success
    • payments.failed
  Gauges (1):
    • queue.size

⚠️  Dynamic Metrics (1) - Cannot be added to dashboard:
  • StatsD.increment in PaymentProcessor (app/services/payment.rb:42)
```

### No Signals Found

```
[diffdash] vX.X.X
[diffdash] No observability signals found in changed files
[diffdash] Dashboard not created
```

## Smoke Testing Features

Diffdash is optimized for smoke testing newly deployed code:

### PR Comment with Signal Summary

When running in GitHub Actions, diffdash automatically posts a comment to your PR with:
- Count of detected logs and metrics
- Breakdown by source class
- Direct link to the Grafana dashboard

### Default Time Range

Dashboards default to **last 30 minutes** - ideal for seeing data from recently deployed code. Adjust in Grafana if you need a different range.

### Getting Started Panel

Each dashboard includes a guidance panel explaining how to see your signals:
1. Deploy the PR to staging
2. Trigger the code path
3. Wait ~30 seconds and refresh

### Environment Default

Set `DIFFDASH_DEFAULT_ENV=staging` to have dashboards pre-filtered to your staging environment - no manual switching needed.

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
| Datadog | `increment`, `incr` | counter |
| Datadog | `gauge`, `set` | gauge |
| Datadog | `timing`, `time` | histogram |
| DogStatsD | (same as Datadog) | |
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

By default, diffdash scans Ruby files while excluding test and config directories.

**Default behavior:**

| Filter | Default Value | Config Key |
|--------|---------------|------------|
| Included extensions | `.rb` | — |
| Excluded suffixes | `_spec.rb`, `_test.rb` | `excluded_suffixes` |
| Excluded directories | `spec`, `test`, `config` | `excluded_directories` |
| Ignored paths | *(none)* | `ignore_paths` |
| Included paths | *(all)* | `include_paths` |

**Customizing in `diffdash.yml`:**

```yaml
# Ignore additional paths
ignore_paths:
  - vendor/
  - lib/legacy/
  - tmp/

# Only scan specific paths (optional whitelist)
include_paths:
  - app/
  - lib/

# Add custom excluded suffixes
excluded_suffixes:
  - _spec.rb
  - _test.rb
  - _integration.rb

# Add custom excluded directories
excluded_directories:
  - spec
  - test
  - config
  - features
```

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

1. **Create `diffdash.yml`** in your repository root with shared settings:

```yaml
grafana:
  url: https://myorg.grafana.net
  folder_id: 42

ignore_paths:
  - vendor/

default_env: staging
```

2. **Add secrets to your repository:**
   - `DIFFDASH_GRAFANA_TOKEN` - Grafana Service Account token with Editor role
   - `GITHUB_TOKEN` - Automatically provided by GitHub Actions (for PR comments)

3. **Create workflow file** `.github/workflows/diffdash-dashboard.yml`:

```yaml
name: Diffdash Dashboard

on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - "**/*.rb"
      - "!spec/**"
      - "!test/**"
  push:
    branches: [main]

permissions:
  contents: read
  pull-requests: write  # Required for PR comments

jobs:
  generate-dashboard:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: ${{ github.event.pull_request.head.sha || github.sha }}

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version

      - name: Ensure branch name is set
        run: |
          BRANCH="${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}"
          if [ -n "$BRANCH" ]; then
            git checkout -B "$BRANCH"
          fi

      - name: Install GitHub CLI
        run: |
          type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
          curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
          && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
          && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
          && sudo apt update \
          && sudo apt install gh -y

      - name: Install diffdash
        run: gem install diffdash

      - name: Generate dashboard
        env:
          DIFFDASH_GRAFANA_URL: ${{ secrets.DIFFDASH_GRAFANA_URL }}
          DIFFDASH_GRAFANA_TOKEN: ${{ secrets.DIFFDASH_GRAFANA_TOKEN }}
          DIFFDASH_GRAFANA_FOLDER_ID: ${{ secrets.DIFFDASH_GRAFANA_FOLDER_ID }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITHUB_PR_NUMBER: ${{ github.event.pull_request.number }}
        run: diffdash --verbose
```

**What this does:**
- Runs on PRs when Ruby files change
- Installs GitHub CLI for automatic PR comments
- Generates a Grafana dashboard scoped to changed files
- Posts a comment to the PR with the dashboard link and signal summary
- Re-runs on push to `main` to update the dashboard

**Note:** The workflow reads `grafana.url` and `grafana.folder_id` from `diffdash.yml`, but you can also set them via secrets (`DIFFDASH_GRAFANA_URL`, `DIFFDASH_GRAFANA_FOLDER_ID`) which take precedence.

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

# Publish to GitHub Packages
# Replace <github_user_name> with your GitHub username (e.g., rossme)
gem push --key github \
  --host https://rubygems.pkg.github.com/<github_user_name> \
  diffdash-0.1.5.gem
```

## Testing Locally with Remote Grafana

To stream local logs/metrics to a remote Grafana instance, run Promtail and Prometheus
alongside your app and then run Diffdash locally.

For a dedicated sandbox app that emits logs/metrics and runs Diffdash in CI,
see [diffdash-test-app](https://github.com/rossme/diffdash-test-app).

**Requirements:**
- Promtail (for logs) and Prometheus (for metrics)
- `bundle exec diffdash` to generate/upload dashboards

**Promtail (Docker)**

```bash
docker run -d \
  --name promtail \
  -v $(pwd)/log:/host/log \
  -v $(pwd)/promtail.yml:/etc/promtail/config.yml \
  grafana/promtail:2.9.0 \
  -config.file=/etc/promtail/config.yml
```

**Configuration files**

In the app where Diffdash is installed, keep:
- `promtail.yml` (Promtail config)
- `prometheus.yml` (Prometheus config)

These live in the app root and are referenced by the commands above.

**Run Diffdash locally**

```bash
bundle exec diffdash
```

## Log Matching Notes

Diffdash builds Loki queries from log messages. The matching strategy depends on
the log message type:

**Plain strings or symbols** - Uses exact literal:
```ruby
logger.info("Hello from Grape API!")
# Query: {env=~"$env", app=~"$app"} |= "Hello from Grape API!"
```

**Interpolated strings** - Extracts static parts:
```ruby
logger.info("Loaded widget #{widget.id}")
# Query: {env=~"$env", app=~"$app"} |= "Loaded widget "
# Matches: "Loaded widget 123", "Loaded widget 456", etc.
```

This approach ensures queries match all instances of interpolated logs while
maintaining exact matching for static messages.

## Grafana Schema Validation

Grafana’s Schema v2 is still experimental, so Diffdash currently validates
against the **v1 dashboard JSON model** (the format used by the Grafana API).
We enforce this via a golden‑file contract test to keep output stable.

To regenerate the fixture after intentional changes:

```bash
bin/regenerate_grafana_fixture
```

Reference:
- Grafana v1 dashboard JSON model: https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/view-dashboard-json-model/#dashboard-json
- Grafana Schema v2 (experimental): https://grafana.com/docs/grafana/latest/as-code/observability-as-code/schema-v2/

## License

MIT
