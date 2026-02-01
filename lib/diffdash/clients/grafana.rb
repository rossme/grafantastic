# frozen_string_literal: true

require 'faraday'
require 'json'

module Diffdash
  module Clients
    # Grafana API HTTP client
    # Responsibilities:
    #   - HTTP communication with Grafana API
    #   - Authentication (Bearer token)
    #   - Error handling for network/API failures
    #
    # NOT responsible for:
    #   - Dashboard structure/JSON generation (see Outputs::Grafana)
    #   - Signal detection (see Detectors::*)
    #   - Business logic or validation
    class Grafana
      class ConnectionError < StandardError; end

      attr_reader :url

      # Initialize Grafana API client
      # @param url [String, nil] Grafana base URL (falls back to ENV['DIFFDASH_GRAFANA_URL'])
      # @param token [String, nil] API token (falls back to ENV['DIFFDASH_GRAFANA_TOKEN'])
      def initialize(url: nil, token: nil)
        @url = url || ENV['DIFFDASH_GRAFANA_URL'] || ENV.fetch('GRAFANA_URL') do
          raise Error, 'DIFFDASH_GRAFANA_URL not set'
        end
        @token = token || ENV['DIFFDASH_GRAFANA_TOKEN'] || ENV.fetch('GRAFANA_TOKEN') do
          raise Error, 'DIFFDASH_GRAFANA_TOKEN not set'
        end
      end

      # Validates connection and authentication to Grafana
      # Uses /api/org endpoint which requires valid auth (unlike /api/health which is public)
      # @return [true] if connection and auth succeed
      # @raise [ConnectionError] if connection fails or auth is invalid
      def health_check!
        response = connection.get('/api/org')

        unless response.success?
          if response.status == 401
            raise ConnectionError, 'Grafana authentication failed (401): Check your DIFFDASH_GRAFANA_TOKEN'
          end

          raise ConnectionError, "Grafana health check failed (#{response.status}): #{response.body}"

        end

        true
      rescue Faraday::Error => e
        raise ConnectionError, "Cannot connect to Grafana at #{@url}: #{e.message}"
      end

      # Upload a dashboard to Grafana
      # @param dashboard_payload [Hash] Complete Grafana dashboard payload
      # @return [Hash] Upload result with :id, :uid, :url, :status
      # @raise [Error] if upload fails
      def upload(dashboard_payload)
        response = connection.post('/api/dashboards/db') do |req|
          req.headers['Content-Type'] = 'application/json'
          req.body = JSON.generate(dashboard_payload)
        end

        unless response.success?
          body = begin
            JSON.parse(response.body)
          rescue StandardError
            { 'message' => response.body }
          end
          raise Error, "Grafana API error (#{response.status}): #{body['message']}"
        end

        result = JSON.parse(response.body)
        {
          id: result['id'],
          uid: result['uid'],
          url: "#{@url}#{result['url']}",
          status: result['status']
        }
      end

      # List all folders the API token has access to
      # @return [Array<Hash>] List of folder metadata
      # @raise [ConnectionError] if request fails
      def list_folders
        response = connection.get('/api/folders')

        unless response.success?
          body = begin
            JSON.parse(response.body)
          rescue StandardError
            { 'message' => response.body }
          end
          raise ConnectionError, "Failed to list folders (#{response.status}): #{body['message']}"
        end

        JSON.parse(response.body)
      rescue Faraday::Error => e
        raise ConnectionError, "Cannot connect to Grafana at #{@url}: #{e.message}"
      end

      private

      def connection
        @connection ||= Faraday.new(url: @url) do |f|
          f.adapter Faraday.default_adapter
          f.headers['Authorization'] = "Bearer #{@token}"
          f.headers['Accept'] = 'application/json'
        end
      end
    end
  end
end
