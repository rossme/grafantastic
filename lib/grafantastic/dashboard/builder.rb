# frozen_string_literal: true

require_relative "../renderers/grafana"

module Grafantastic
  module Dashboard
    # DEPRECATED: This class is maintained for backward compatibility
    # Use Grafantastic::Renderers::Grafana directly instead
    # TODO: Remove in next major version
    class Builder
      def initialize(title:, signals:, config:)
        @title = title
        @signals = signals
        @config = config
      end

      def build
        # Delegate to new Renderer for cleaner architecture
        renderer = Renderers::Grafana.new(
          signals: @signals,
          title: @title,
          folder_id: @config.grafana_folder_id
        )
        renderer.render
      end
    end
  end
end
