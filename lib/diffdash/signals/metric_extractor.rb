# frozen_string_literal: true

require_relative '../signal/counter'
require_relative '../signal/gauge'
require_relative '../signal/histogram'
require_relative '../signal/summary'

module Diffdash
  module Signals
    class MetricExtractor
      class << self
        def extract(visitor)
          visitor.metric_calls.filter_map do |metric_call|
            next unless metric_call[:name]

            # Create typed signal based on metric_type
            signal_class = case metric_call[:metric_type]
                           when :counter then Diffdash::Signal::Counter
                           when :gauge then Diffdash::Signal::Gauge
                           when :histogram then Diffdash::Signal::Histogram
                           when :summary then Diffdash::Signal::Summary
                           else Diffdash::Signal::Counter # Default to counter
                           end

            signal_class.new(
              name: metric_call[:name],
              source_file: visitor.file_path,
              defining_class: metric_call[:defining_class],
              inheritance_depth: visitor.inheritance_depth,
              metadata: {
                line: metric_call[:line]
              }
            )
          end
        end
      end
    end
  end
end
