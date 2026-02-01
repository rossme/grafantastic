# frozen_string_literal: true

require_relative '../signal/log'

module Diffdash
  module Signals
    class LogExtractor
      class << self
        def extract(visitor)
          visitor.log_calls.filter_map do |log_call|
            event_name = log_call[:event_name] || generate_fallback_name(log_call)

            # Use explicit Log signal type
            Diffdash::Signal::Log.new(
              name: event_name,
              source_file: visitor.file_path,
              defining_class: log_call[:defining_class],
              inheritance_depth: visitor.inheritance_depth,
              metadata: {
                level: log_call[:level],
                line: log_call[:line],
                interpolated: log_call[:interpolated] || false
              }
            )
          end
        end

        private

        def generate_fallback_name(log_call)
          # Generate stable identifier from class + level + line
          components = [
            log_call[:defining_class],
            log_call[:level],
            log_call[:line]
          ].compact

          digest = Digest::SHA256.hexdigest(components.join(':'))
          "log_#{digest[0, 8]}"
        end
      end
    end
  end
end
