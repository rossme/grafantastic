# frozen_string_literal: true

# Diffdash: Observability focused on the code you're shipping, not the noise.
#
# Automatically generates Grafana dashboards scoped to your PR's changes,
# so you see exactly the logs and metrics that matter for smoke testing.

require "json"
require "digest"

begin
  require "dotenv/load"
rescue LoadError
  # dotenv is optional
end

require_relative "diffdash/version"
require_relative "diffdash/config"
require_relative "diffdash/git_context"
require_relative "diffdash/file_filter"
require_relative "diffdash/signals/signal"
require_relative "diffdash/ast/parser"
require_relative "diffdash/ast/visitor"
require_relative "diffdash/ast/ancestor_resolver"
require_relative "diffdash/detectors/ruby_detector"
require_relative "diffdash/clients/grafana"
require_relative "diffdash/services/signal_collector"
require_relative "diffdash/services/pr_commenter"
require_relative "diffdash/formatters/dashboard_title"
require_relative "diffdash/signals/log_extractor"
require_relative "diffdash/signals/metric_extractor"
require_relative "diffdash/validation/limits"

# Engine (vendor-agnostic)
require_relative "diffdash/engine/change_set"
require_relative "diffdash/engine/signal_query"
require_relative "diffdash/engine/signal_bundle"
require_relative "diffdash/engine/signal"
require_relative "diffdash/engine/engine"

# Outputs (vendor-specific adapters)
require_relative "diffdash/outputs/base"
require_relative "diffdash/outputs/grafana"
require_relative "diffdash/outputs/json"

# CLI
require_relative "diffdash/cli/runner"

module Diffdash
  class Error < StandardError; end
  class LimitExceededError < Error; end
  class GitContextError < Error; end
end
