# Diffdash Documentation

Comprehensive documentation for Diffdash - PR-scoped observability dashboard generator.

## Table of Contents

- [Installation](#installation)
- [Configuration](#configuration)
- [CLI Reference](#cli-reference)
- [Output Adapters](#output-adapters)
- [Signal Detection](#signal-detection)
- [GitHub Actions](#github-actions)
- [Local Development](#local-development)
- [Troubleshooting](#troubleshooting)

---

## Installation

### From RubyGems

```bash
gem install diffdash
```

### From GitHub Packages

```ruby
# Gemfile
source "https://rubygems.pkg.github.com/rossme" do
  gem "diffdash"
end
```

### From Source

```bash
gem build diffdash.gemspec
gem install diffdash-*.gem
```

---

## Configuration

### Configuration File

Create `diffdash.yml` in your repository root:

```yaml
# Output adapters (grafana, datadog, kibana, json)
outputs:
  - grafana

# Grafana settings
grafana:
  url: https://myorg.grafana.net
  folder_id: 42

# Datadog settings (if using datadog output)
datadog:
  site: datadoghq.com  # or datadoghq.eu, etc.

# Kibana settings (if using kibana output)
kibana:
  url: https://my-deployment.kb.us-east-1.aws.elastic.cloud
  space_id: default
  index_pattern: logs-*

# General settings
default_env: production
app_name: my-service

# File filtering
ignore_paths:
  - vendor/
  - lib/legacy/

include_paths:        # Optional whitelist
  - app/
  - lib/

excluded_suffixes:
  - _spec.rb
  - _test.rb

excluded_directories:
  - spec
  - test
  - config

# Signal filtering
signals:
  # How to handle interpolated logs (include, warn, exclude)
  interpolated_logs: include
```

### Signal Filtering

Control how interpolated logs are handled in dashboards:

```yaml
signals:
  interpolated_logs: exclude  # Options: include, warn, exclude
```

| Value | Behavior |
|-------|----------|
| `include` | Include all logs in dashboard (default) |
| `warn` | Include all, but show CLI warning suggesting structured logging |
| `exclude` | Exclude interpolated logs from dashboard |

**Environment variable:** `DIFFDASH_INTERPOLATED_LOGS`

```bash
# Exclude interpolated logs via env var
DIFFDASH_INTERPOLATED_LOGS=exclude diffdash grafana
```

### Environment Variables

Environment variables **always override** config file values.

#### Grafana

| Variable | Required | Description |
|----------|----------|-------------|
| `DIFFDASH_GRAFANA_URL` | Yes* | Grafana instance URL |
| `DIFFDASH_GRAFANA_TOKEN` | Yes | Service Account token (Editor role) |
| `DIFFDASH_GRAFANA_FOLDER_ID` | No | Target folder ID |

#### Datadog

| Variable | Required | Description |
|----------|----------|-------------|
| `DIFFDASH_DATADOG_API_KEY` | Yes | Datadog API key |
| `DIFFDASH_DATADOG_APP_KEY` | Yes | Datadog Application key |
| `DIFFDASH_DATADOG_SITE` | No | Datadog site (default: `datadoghq.com`) |

#### Kibana

| Variable | Required | Description |
|----------|----------|-------------|
| `DIFFDASH_KIBANA_URL` | Yes | Kibana instance URL |
| `DIFFDASH_KIBANA_API_KEY` | Yes** | Kibana API key |
| `DIFFDASH_KIBANA_USERNAME` | Yes** | Kibana username (if not using API key) |
| `DIFFDASH_KIBANA_PASSWORD` | Yes** | Kibana password (if not using API key) |
| `DIFFDASH_KIBANA_SPACE_ID` | No | Kibana space ID (default: `default`) |
| `DIFFDASH_KIBANA_INDEX_PATTERN` | No | Index pattern (default: `logs-*`) |

**Either API key OR username/password required*

#### General

| Variable | Description |
|----------|-------------|
| `DIFFDASH_OUTPUTS` | Comma-separated outputs (default: `grafana`) |
| `DIFFDASH_DRY_RUN` | Set to `true` for dry-run mode |
| `DIFFDASH_DEFAULT_ENV` | Default environment filter |
| `DIFFDASH_APP_NAME` | Override app name |

### Configuration Precedence

1. **Environment variables** (highest priority)
2. **`--config` flag** specified file
3. **Config file in current directory**
4. **Config file in git root**
5. **Default values** (lowest priority)

### Security Note

API tokens are **only loaded from environment variables** — never from config files. This prevents accidental commits of secrets.

---

## CLI Reference

```bash
diffdash [output] [options]
```

### Outputs

| Output | Description |
|--------|-------------|
| `grafana` | Generate and upload Grafana dashboard |
| `datadog` | Generate and upload Datadog dashboard |
| `kibana` | Generate and upload Kibana dashboard |
| `json` | Output raw signal data as JSON |
| *(none)* | Use outputs from config or `DIFFDASH_OUTPUTS` |

### Commands

| Command | Description |
|---------|-------------|
| `lint` | Check for observability best practices |
| `grafana folders` | List available Grafana folders |
| `kibana folders` | List available Kibana spaces |

### Options

| Option | Description |
|--------|-------------|
| `--config FILE` | Path to configuration file |
| `--dry-run` | Generate without uploading |
| `--list-signals` | Show detected signals only |
| `--verbose` | Detailed output |
| `--version` | Show version |
| `--help` | Show help |

### Examples

```bash
# Generate Grafana dashboard
diffdash grafana

# Generate Kibana dashboard with verbose output
diffdash kibana --verbose

# Generate Datadog dashboard without uploading
diffdash datadog --dry-run

# List available folders/spaces
diffdash grafana folders
diffdash kibana folders

# Check for observability best practices
diffdash lint
diffdash lint --verbose

# See detected signals without uploading
diffdash --list-signals

# Use multiple outputs (via env var)
DIFFDASH_OUTPUTS=grafana,json diffdash
```

---

## Output Adapters

Diffdash supports multiple observability backends:

### Grafana

Generates Grafana dashboard JSON with:
- Log panels using Loki queries
- Metric panels using PromQL
- Template variables for `app`, `env`, `datasource`
- PR deployment annotations

**Requirements:**
- Grafana Service Account token with Editor role
- Loki datasource for logs
- Prometheus datasource for metrics

### Datadog

Generates Datadog dashboard JSON with:
- Log stream widgets
- Timeseries widgets for metrics
- Template variables

**Requirements:**
- Datadog API key and Application key

### Kibana

Generates Kibana Saved Objects (NDJSON) with:
- Saved searches showing log entries
- Metric visualizations
- Index pattern configuration

**Requirements:**
- Kibana API key or username/password
- Elasticsearch with your log data

**Note:** For Elastic Cloud Serverless, set `DIFFDASH_KIBANA_INDEX_PATTERN` to match your data stream (e.g., `logs-myapp-default`).

### JSON

Outputs raw signal data as JSON to stdout. Useful for debugging or piping to other tools.

---

## Signal Detection

### Supported Log Patterns

```ruby
logger.info("message")
logger.debug("message")
logger.warn("message")
logger.error("message")
logger.fatal("message")
Rails.logger.info("message")
@logger.info("message")
```

### Supported Metric Patterns

| Client | Methods | Metric Type |
|--------|---------|-------------|
| Prometheus | `counter().increment` | counter |
| Prometheus | `gauge().set` | gauge |
| Prometheus | `histogram().observe` | histogram |
| StatsD | `increment`, `incr` | counter |
| StatsD | `gauge`, `set` | gauge |
| StatsD | `timing`, `time` | histogram |
| Datadog | `increment`, `incr` | counter |
| Datadog | `gauge`, `set` | gauge |
| Hesiod | `emit` | counter |
| Hesiod | `gauge` | gauge |

### Metric Constant Resolution

Diffdash automatically resolves metric constants defined in centralized files:

```ruby
# app/services/metrics.rb
module Metrics
  RequestTotal = Hesiod.register_counter("request_total")
  QueueDepth = Hesiod.register_gauge("queue_depth")
end

# app/jobs/worker.rb
class Worker
  def perform
    Metrics::RequestTotal.increment  # ✅ Resolved to "request_total"
    Metrics::QueueDepth.set(5)       # ✅ Resolved to "queue_depth"
  end
end
```

Diffdash scans these common locations for metric definitions:
- `app/services/metrics.rb`
- `lib/metrics.rb`
- `app/lib/metrics.rb`
- `config/initializers/metrics.rb`

### Log Message Handling

**Plain strings/symbols** — exact match:
```ruby
logger.info("user_created")
# Grafana: |= "user_created"
# Kibana: message:"user_created"
```

**Interpolated strings** — static parts extracted:
```ruby
logger.info("Loaded widget #{id}")
# Grafana: |= "Loaded widget "
# Kibana: message:"Loaded widget "
```

### Inheritance Support

Signals are extracted from:
- The changed class/module (depth 0)
- Parent classes (up to 5 levels)
- Included modules
- Prepended modules

---

## Linting

The `diffdash lint` command checks for observability best practices.

### Interpolated Logs

Logs with string interpolation are harder to query:

```ruby
# ⚠️ Interpolated - hard to match in Loki/Kibana
logger.info("User #{user.id} logged in")
# Matches on: "User " and " logged in"

# ✅ Structured - exact match
logger.info("user_logged_in", user_id: user.id)
# Matches on: "user_logged_in"
```

### Usage

```bash
# Check for issues
diffdash lint

# Show details for each issue
diffdash lint --verbose
```

### Output

```
[diffdash] Linting observability patterns...
[diffdash] Analyzing 4 files...

Found 3 logs with string interpolation.
Consider structured logging for better observability matching.

Example:
  Before: logger.info("User #{user.id} logged in")
  After:  logger.info("user_logged_in", user_id: user.id)

Run 'diffdash lint --verbose' for details.
```

During dashboard generation, a warning is shown if interpolated logs are found:

```
[diffdash] ⚠ Found 3 interpolated logs (run 'diffdash lint' for suggestions)
```

---

## GitHub Actions

### Basic Workflow

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
  pull-requests: write

jobs:
  generate-dashboard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version

      - name: Set branch name
        run: |
          BRANCH="${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}"
          git checkout -B "$BRANCH"

      - name: Install diffdash
        run: gem install diffdash

      - name: Generate dashboard
        env:
          DIFFDASH_GRAFANA_URL: ${{ secrets.DIFFDASH_GRAFANA_URL }}
          DIFFDASH_GRAFANA_TOKEN: ${{ secrets.DIFFDASH_GRAFANA_TOKEN }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITHUB_PR_NUMBER: ${{ github.event.pull_request.number }}
        run: diffdash --verbose
```

### Required Secrets

| Secret | Description |
|--------|-------------|
| `DIFFDASH_GRAFANA_URL` | Grafana instance URL |
| `DIFFDASH_GRAFANA_TOKEN` | Grafana Service Account token |
| `GITHUB_TOKEN` | Auto-provided for PR comments |

---

## Local Development

### Testing with Remote Grafana

1. **Install Promtail** for log shipping:

```bash
docker run -d \
  --name promtail \
  -v $(pwd)/log:/host/log \
  -v $(pwd)/promtail.yml:/etc/promtail/config.yml \
  grafana/promtail:2.9.0 \
  -config.file=/etc/promtail/config.yml
```

2. **Create `promtail.yml`**:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: https://logs-prod-xxx.grafana.net/loki/api/v1/push
    basic_auth:
      username: <your-user-id>
      password: <your-api-key>

scrape_configs:
  - job_name: myapp
    static_configs:
      - targets: [localhost]
        labels:
          app: myapp
          env: local
          __path__: /host/log/*.log
```

3. **Run Diffdash**:

```bash
bundle exec diffdash --verbose
```

### Testing with Kibana

1. Set up Elastic Agent to ship logs to your Elasticsearch cluster
2. Configure environment variables:

```bash
export DIFFDASH_KIBANA_URL=https://my-deployment.kb.region.aws.elastic.cloud
export DIFFDASH_KIBANA_API_KEY=your-api-key
export DIFFDASH_KIBANA_INDEX_PATTERN=logs-myapp-default
export DIFFDASH_OUTPUTS=kibana
```

3. Run Diffdash:

```bash
bundle exec diffdash --verbose
```

### Test App

For a complete example with logs, metrics, and CI integration, see:
[diffdash-test-app](https://github.com/rossme/diffdash-test-app)

---

## Troubleshooting

### No signals found

- Check that you have changed Ruby files in your branch
- Ensure files aren't excluded by `ignore_paths` or `excluded_directories`
- Use `--list-signals` to debug detection

### Grafana authentication failed (401)

- Verify `DIFFDASH_GRAFANA_TOKEN` is set correctly
- Ensure the Service Account has Editor role
- Check the token hasn't expired

### Kibana panels show no data

- Verify `DIFFDASH_KIBANA_INDEX_PATTERN` matches your actual data stream
- Check the time range in Kibana includes recent data
- Ensure logs are being shipped to Elasticsearch

### Interpolated logs warning

Logs with interpolation are detected but harder to query:

```ruby
# ⚠️ Interpolated - harder to match
logger.info("User #{user.id} logged in")

# ✅ Structured - exact match
logger.info("user_logged_in", user_id: user.id)
```

Run `diffdash lint --verbose` to see all interpolated logs.

### Dynamic metrics warning

Metrics with runtime-determined names cannot be analyzed:

```ruby
# ❌ Dynamic - cannot be detected
StatsD.increment("#{entity.type}.processed")

# ✅ Static - will be detected
StatsD.increment("entity.processed", tags: { type: entity.type })
```

### Guard Rails

Hard limits prevent noisy dashboards:

| Signal Type | Max Count |
|-------------|-----------|
| Logs | 10 |
| Metrics | 10 |
| Total Panels | 12 |

Excess signals are truncated with a warning.

---

## Contributing

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

---

## License

MIT
