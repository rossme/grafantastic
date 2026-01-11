# frozen_string_literal: true

require_relative "clients/grafana"

module Grafantastic
  # DEPRECATED: This class is maintained for backward compatibility
  # Use Grafantastic::Clients::Grafana directly instead
  # TODO: Remove in next major version
  class GrafanaClient < Clients::Grafana
    # Inherit ConnectionError for backward compatibility
    ConnectionError = Clients::Grafana::ConnectionError
  end
end
