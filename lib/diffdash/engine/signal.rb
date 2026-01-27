# frozen_string_literal: true

module Diffdash
  module Engine
    # Converts domain signals into vendor-agnostic SignalQuery objects.
    class Signal
      def self.from_domain(signal, time_range:)
        case signal.type
        when :log
          SignalQuery.new(
            type: :logs,
            name: signal.name,
            time_range: time_range,
            metadata: signal.metadata,
            source_file: signal.source_file,
            defining_class: signal.defining_class
          )
        when :metric
          SignalQuery.new(
            type: :metrics,
            name: signal.name,
            time_range: time_range,
            metadata: signal.metadata,
            source_file: signal.source_file,
            defining_class: signal.defining_class
          )
        else
          nil
        end
      end
    end
  end
end
