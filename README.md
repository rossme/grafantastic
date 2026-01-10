# Grafantastic

PR-scoped observability signal extractor and Grafana dashboard generator.

## Overview

Grafantastic statically analyzes Ruby source code changed in a Pull Request and generates a Grafana dashboard JSON containing panels relevant to the observability signals found in that code.

## Installation

```bash
bundle install
```

Or install the gem:

```bash
gem build grafantastic.gemspec
gem install grafantastic-0.1.0.gem
```

## Usage

### Generate Dashboard (CLI)

```bash
# Generate dashboard JSON to stdout
bundle exec grafantastic

# With verbose output
bundle exec grafantastic --verbose

# Dry run (never upload)
bundle exec grafantastic --dry-run
```

### Using Make

```bash
# Generate dashboard
make dashboard

# Verbose mode
make dashboard-verbose

# Dry run
make dashboard-dry
```

### Environment Variables

Create a `.env` file:

```bash
GRAFANA_URL=https://grafana.example.com
GRAFANA_TOKEN=your-api-token
GRAFANA_FOLDER_ID=123          # Optional
GRAFANTASTIC_DRY_RUN=true        # Optional, forces dry-run mode
```

## Observability Signals

The gem detects:

### Logs

- `logger.info`, `logger.error`, `logger.warn`, etc.
- `Rails.logger.*`

### Metrics

- Prometheus: `Prometheus.counter`, `Prometheus.histogram`, etc.
- StatsD: `StatsD.increment`, `StatsD.timing`, etc.
- Hesiod: `Hesiod.emit`

## Guard Rails

Hard limits are enforced:

| Signal Type | Max Count |
|-------------|-----------|
| Logs        | 10        |
| Metrics     | 10        |
| Events      | 5         |
| Total Panels| 12        |

If any limit is exceeded, the gem aborts with a clear error message.

## File Filtering

**Included:**
- Files ending with `.rb`
- Ruby application code

**Excluded:**
- `*_spec.rb`, `*_test.rb`
- Files in `/spec/`, `/test/`, `/config/`
- Non-Ruby files

## Inheritance

Signals are extracted from:
- The touched class/module (depth = 0)
- Its direct parent class (depth = 1)

Grandparents and deeper are not traversed.

## Output

The gem outputs valid Grafana dashboard JSON to STDOUT. Errors and progress information go to STDERR.

If no observability signals are found, a dashboard with a single text panel is generated.

## GitHub Actions Integration

Grafantastic works great as a GitHub Action that automatically creates dashboards for PRs.

### Setup

1. **Add secrets to your repository:**
   - `GRAFANA_URL` - Your Grafana instance URL (e.g., `https://myorg.grafana.net`)
   - `GRAFANA_TOKEN` - Service Account token with Editor role
   - `GRAFANA_FOLDER_ID` (optional) - Folder ID for dashboards

2. **Copy the workflow file:**
   ```bash
   cp .github/workflows/pr-dashboard.yml YOUR_REPO/.github/workflows/
   ```

3. **That's it!** When a PR is opened or updated with Ruby file changes:
   - Grafantastic analyzes the changed files
   - Creates/updates a dashboard in Grafana
   - Posts a comment on the PR with the dashboard link

### What it looks like

When a developer opens a PR, they'll see a comment like:

> ## 📊 Observability Dashboard
>
> A Grafana dashboard has been generated for the observability signals in this PR.
>
> **[View Dashboard](https://grafana.example.com/d/abc123/feature-branch)**

### Workflow triggers

The action runs on:
- PR opened
- PR synchronized (new commits pushed)
- PR reopened

It only triggers when Ruby files (excluding specs/tests) are changed.

## Architecture

```
Ruby source code
       ↓
AST analysis (parser gem)
       ↓
Observability signals
       ↓
Validation (guard rails)
       ↓
Grafana dashboard JSON
       ↓
(GitHub Action) PR comment with link
```

## Development

```bash
# Install dependencies
make install

# Run linter
make lint

# Run tests
make test
```

## License

MIT
