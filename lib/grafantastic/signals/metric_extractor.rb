# frozen_string_literal: true

module Grafantastic
  module Signals
    class MetricExtractor
      class << self
        def extract(visitor)
          visitor.metric_calls.filter_map do |metric_call|
            next unless metric_call[:name]

            Signal.new(
              type: :metric,
              name: metric_call[:name],
              source_file: visitor.file_path,
              defining_class: metric_call[:defining_class],
              inheritance_depth: visitor.inheritance_depth,
              metadata: {
                metric_type: metric_call[:metric_type],
                line: metric_call[:line]
              }
            )
          end
        end
      end
    end
  end
end
