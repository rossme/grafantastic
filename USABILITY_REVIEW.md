# Diffdash Usability Review

As a Ruby software engineer working in a Rails monolith environment using Grafana and Datadog, I have reviewed `Diffdash` from a usability perspective. Below are my findings regarding what works well, what's missing, and how it could be improved for daily workflows.

## 👍 Things I Like

1.  **"Observability for the code you ship"**: The core concept is excellent. Instead of hunting through a massive "Monolith Production" dashboard to find the 3 metrics I just added, this tool gives me a focused view of exactly what changed. It reduces cognitive load significantly during deployment.
2.  **Smart PR Commenting**: I love that the `PrCommenter` service updates an existing comment instead of spamming the PR timeline with new comments on every push. The summary of detected signals (e.g., "Detected 2 logs and 3 metrics") directly in the PR is very helpful for reviewers.
3.  **Static Analysis Approach**: Since it parses the AST, it's fast and doesn't require running the app or waiting for a test suite. It catches typos in metric names before they merge.
4.  **Inheritance & Module Support**: It correctly handles Ruby semantics. If I change a class that includes a `Loggable` module, it knows to look for logs defined in that module. This shows it was built by someone who understands real-world Ruby codebases.
5.  **Guard Rails**: The hard limits (max 12 panels) are a smart default to prevent generating unusable, massive dashboards. It forces focus.

## 🧐 Things I'd Like to See (Missing Features)

1.  **Datadog Dashboard Support**: You mentioned we use Datadog, but `Diffdash` currently only outputs Grafana dashboards. While it can *detect* Datadog client calls (`Datadog.increment`), it generates a Grafana dashboard for them. If my team uses Datadog for visualization, I'm out of luck. I'd like to see an `Outputs::Datadog` adapter.
2.  **Configuration File (`diffdash.yml`)**: Currently, configuration relies heavily on Environment Variables (`DIFFDASH_GRAFANA_URL`, etc.). A `diffdash.yml` file would allow us to commit shared configuration (like `default_env`, `folder_id`, and `ignore_paths`) to the repository, ensuring consistency across the team.
3.  **Customizable Detection Patterns**: If we use a wrapper around our logger (e.g., `MyCorp::Logger.info`), `Diffdash` might miss it. I'd like to define custom patterns in the config, like `log_patterns: ["MyCorp::Logger.*"]`.
4.  **"Copy Query" Feature**: Sometimes I don't need a whole dashboard; I just want the Loki or PromQL query to paste into Explore. A CLI flag like `--print-queries` would be great.

## 👎 Things I Don't Like

1.  **Hardcoded Limits**: The limits (`MAX_LOGS = 10`, `MAX_PANELS = 12`) are hardcoded in `Config.rb`. While good defaults, they should be overridable via config. For a major refactor, I might legitimately need to monitor 15 metrics.
2.  **Dynamic Metric Blind Spot**: The tool completely ignores dynamic metrics (e.g., `Prometheus.counter("job_#{status}")`). While I understand the technical limitation of static analysis, it creates a false sense of security if I rely on the dashboard and miss key metrics. The warning output is there, but it's easy to miss in CI logs.
3.  **Setup Friction**: Getting the Grafana Service Account token and Folder ID requires admin access or asking DevOps. A CLI "wizard" (`diffdash setup`) that validates the connection would be smoother than manually editing `.env`.

## 🚫 Things I'd NEVER Use

1.  **If it required code changes**: I would never use this if it forced me to rewrite my code just to be detected (e.g., "You must use string literals for metric names"). Fortunately, it seems to handle most standard cases well, but if I have to refactor my dynamic metaprogramming just for this tool, I won't use it.
2.  **If it spammed PRs**: If the GitHub Action posted a new comment on every commit, I would disable it immediately. (Verified: It *does not* do this; it updates the existing comment, which is the correct behavior).

## 🚀 Improvements for Daily Work

To make this indispensable for my daily workflow, I would prioritize:

1.  **Add `diffdash.yml` support**:
    ```yaml
    # .diffdash.yml
    grafana:
      folder_id: 123
      default_env: staging
    limits:
      max_panels: 20
    patterns:
      logs:
        - "AuditLogger.log"
    ```
2.  **Interactive CLI Mode**:
    - `diffdash watch`: Watch file changes locally and update a "Dev" dashboard in real-time as I code.
3.  **Linter Integration**:
    - Make it a Rubocop plugin? "Warning: You are adding a dynamic metric that cannot be monitored statically."
4.  **Hyperlink to Code**:
    - In the Grafana dashboard, add a link back to the specific line of code in GitHub that generates that metric.

## Summary

`Diffdash` is a promising tool that solves a real pain point: visibility into changes. Its static analysis approach is efficient, and the PR integration is well-executed. However, for a team using both Grafana and Datadog, the lack of Datadog output is a significant gap. Adding a configuration file and making limits adjustable would make it production-ready for larger teams.
