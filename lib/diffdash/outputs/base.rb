# frozen_string_literal: true

module Diffdash
  module Outputs
    # Base adapter interface for output backends.
    class Base
      def call(signal_bundle)
        render(signal_bundle)
      end

      def render(_signal_bundle)
        raise NotImplementedError, 'Output adapter must implement #render'
      end
    end
  end
end
