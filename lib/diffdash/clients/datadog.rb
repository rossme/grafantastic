# frozen_string_literal: true

require 'faraday'
require 'json'

module Diffdash
  module Clients
    # Datadog API HTTP client
    class Datadog
      class ConnectionError < StandardError; end

      attr_reader :url

      def initialize(api_key: nil, app_key: nil, site: nil)
        @site = site || ENV['DIFFDASH_DATADOG_SITE'] || 'datadoghq.com'
        @url = "https://api.#{@site}"
        @api_key = api_key || ENV['DIFFDASH_DATADOG_API_KEY'] || raise(Error, 'DIFFDASH_DATADOG_API_KEY not set')
        @app_key = app_key || ENV['DIFFDASH_DATADOG_APP_KEY'] || raise(Error, 'DIFFDASH_DATADOG_APP_KEY not set')
      end

      # Validates connection to Datadog
      def health_check!
        response = connection.get('/api/v1/validate')

        unless response.success?
          if response.status == 403
            raise ConnectionError, 'Datadog authentication failed (403): Check your API/APP keys'
          end

          raise ConnectionError, "Datadog health check failed (#{response.status}): #{response.body}"

        end

        true
      rescue Faraday::Error => e
        raise ConnectionError, "Cannot connect to Datadog at #{@url}: #{e.message}"
      end

      # Upload a dashboard to Datadog
      # @param dashboard_payload [Hash] Complete Datadog dashboard payload
      # @return [Hash] Upload result with :id, :url
      def upload_dashboard(dashboard_payload)
        response = connection.post('/api/v1/dashboard') do |req|
          req.headers['Content-Type'] = 'application/json'
          req.body = JSON.generate(dashboard_payload)
        end

        unless response.success?
          body = begin
            JSON.parse(response.body)
          rescue StandardError
            { 'errors' => [response.body] }
          end
          error_msg = body['errors']&.first || body['message'] || 'Unknown error'
          raise Error, "Datadog API error (#{response.status}): #{error_msg}"
        end

        result = JSON.parse(response.body)
        {
          id: result['id'],
          url: "https://app.#{@site}/dashboard/#{result['id']}"
        }
      end

      private

      def connection
        @connection ||= Faraday.new(url: @url) do |f|
          f.adapter Faraday.default_adapter
          f.headers['DD-API-KEY'] = @api_key
          f.headers['DD-APPLICATION-KEY'] = @app_key
          f.headers['Accept'] = 'application/json'
        end
      end
    end
  end
end
