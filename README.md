# Diffdash

**PR-scoped observability dashboard generator.**

Diffdash analyzes Ruby code changed in a Pull Request and generates dashboards for Grafana, Datadog, or Kibana — showing only the logs and metrics relevant to your changes.

No more searching through dashboards with thousands of metrics. See exactly what matters to _your_ code.

## Quick Start

```bash
gem install diffdash
```

Create `diffdash.yml`:

```yaml
outputs:
  - grafana

grafana:
  url: https://myorg.grafana.net
  folder_id: 42
```

Set your token and run:

```bash
export DIFFDASH_GRAFANA_TOKEN=glsa_xxxxxxxxxxxx
diffdash
```

## Supported Backends

| Backend | Output | API Upload |
|---------|--------|------------|
| **Grafana** | Loki logs, PromQL metrics | ✅ |
| **Datadog** | Log streams, timeseries | ✅ |
| **Kibana** | Saved searches, metrics | ✅ |
| **JSON** | Raw signal data | — |

```bash
# Use multiple outputs
DIFFDASH_OUTPUTS=grafana,datadog diffdash

# Kibana
DIFFDASH_OUTPUTS=kibana diffdash
```

## CLI

```bash
diffdash                  # Generate and upload dashboard
diffdash --dry-run        # Generate JSON only
diffdash --list-signals   # Show detected signals
diffdash --verbose        # Detailed output
diffdash folders          # List Grafana folders
```

## What It Detects

**Logs:**
```ruby
logger.info("user_created")
Rails.logger.error("payment_failed")
```

**Metrics:**
```ruby
StatsD.increment("orders.processed")
Prometheus.counter(:requests_total).increment
Hesiod.emit("cache.hit")
```

## GitHub Actions

```yaml
name: Diffdash Dashboard

on:
  pull_request:
    paths: ["**/*.rb", "!spec/**"]

jobs:
  dashboard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: ruby/setup-ruby@v1

      - run: gem install diffdash

      - run: diffdash --verbose
        env:
          DIFFDASH_GRAFANA_URL: ${{ secrets.DIFFDASH_GRAFANA_URL }}
          DIFFDASH_GRAFANA_TOKEN: ${{ secrets.DIFFDASH_GRAFANA_TOKEN }}
```

## Configuration

Environment variables always override config file values.

| Variable | Description |
|----------|-------------|
| `DIFFDASH_GRAFANA_URL` | Grafana URL |
| `DIFFDASH_GRAFANA_TOKEN` | Grafana Service Account token |
| `DIFFDASH_DATADOG_API_KEY` | Datadog API key |
| `DIFFDASH_DATADOG_APP_KEY` | Datadog Application key |
| `DIFFDASH_KIBANA_URL` | Kibana URL |
| `DIFFDASH_KIBANA_API_KEY` | Kibana API key |
| `DIFFDASH_OUTPUTS` | Comma-separated outputs |

See [DOCS.md](DOCS.md) for full configuration reference.

## Example

For a complete working example with CI integration, see:
**[diffdash-test-app](https://github.com/rossme/diffdash-test-app)**

## Documentation

📖 **[Full Documentation](DOCS.md)** — Configuration, signal detection, GitHub Actions, troubleshooting.

## License

MIT
