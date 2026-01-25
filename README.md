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
DIFFDASH_GRAFANA_URL=https://myorg.grafana.net
DIFFDASH_GRAFANA_TOKEN=glsa_xxxxxxxxxxxx
DIFFDASH_GRAFANA_FOLDER_ID=42  # optional
DIFFDASH_OUTPUTS=grafana,json
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

Set DIFFDASH_GRAFANA_FOLDER_ID in your .env file to use a specific folder
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
- `--version` - Show version number
- `--help` - Show help

## Environment Variables

Set these in a `.env` file in your project root:

| Variable | Required | Description |
|----------|----------|-------------|
| `DIFFDASH_GRAFANA_URL` | Yes | Grafana instance URL (e.g., `https://myorg.grafana.net`) |
| `DIFFDASH_GRAFANA_TOKEN` | Yes | Grafana API token (Service Account token with Editor role) |
| `DIFFDASH_GRAFANA_FOLDER_ID` | No | Target folder ID for dashboards |
| `DIFFDASH_OUTPUTS` | No | Comma-separated outputs (default: `grafana`) |
| `DIFFDASH_DRY_RUN` | No | Set to `true` to force dry-run mode |
| `DIFFDASH_DEFAULT_ENV` | No | Default environment filter (default: `production`) |
| `DIFFDASH_APP_NAME` | No | Override app name in dashboard (defaults to Git repo name) |
| `DIFFDASH_PR_COMMENT` | No | Set to `false` to disable PR comments with dashboard link |
| `DIFFDASH_PR_DEPLOY_ANNOTATION_EXPR` | No | PromQL expr for PR deployment annotation |

## Output

When signals are found, JSON is output first, then a summary:

```
[diffdash] vX.X.X
{ ... dashboard JSON ... }

[diffdash] Dashboard created with 4 panels: 2 logs, 3 counters, 1 gauge, 1 histogram
[diffdash] Uploaded to: https://myorg.grafana.net/d/abc123/feature-branch
[diffdash] Note: 1 dynamic metric could not be added
```

In dry-run mode:

```
[diffdash] vX.X.X
{ ... dashboard JSON ... }

[diffdash] Dashboard created with 4 panels: 2 logs, 3 counters, 1 gauge, 1 histogram
[diffdash] Mode: dry-run (not uploaded)
```

**If no signals are found, no dashboard is created:**

```
[diffdash] vX.X.X
[diffdash] No observability signals found in changed files
[diffdash] Dashboard not created
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
   - `DIFFDASH_GRAFANA_URL` - Your Grafana instance URL
   - `DIFFDASH_GRAFANA_TOKEN` - Service Account token with Editor role
   - `DIFFDASH_GRAFANA_FOLDER_ID` (optional) - Folder ID for dashboards

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
          DIFFDASH_GRAFANA_URL: ${{ secrets.DIFFDASH_GRAFANA_URL }}
          DIFFDASH_GRAFANA_TOKEN: ${{ secrets.DIFFDASH_GRAFANA_TOKEN }}
          DIFFDASH_GRAFANA_FOLDER_ID: ${{ secrets.DIFFDASH_GRAFANA_FOLDER_ID }}
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

Diffdash builds Loki queries from log messages. For **plain string or symbol**
messages, it uses the exact literal in the query:

```text
{env=~"$env", app=~"$app"} |= "Hello from Grape API!"
```

For **interpolated or dynamic strings**, Diffdash falls back to a sanitized
identifier to keep queries stable.

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
