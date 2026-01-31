# frozen_string_literal: true

require "faraday"
require "faraday/multipart"
require "json"

module Diffdash
  module Clients
    # Kibana Saved Objects API HTTP client
    # 
    # Kibana uses the Saved Objects API for dashboard import/export.
    # Requires either API key authentication or basic auth.
    class Kibana
      class ConnectionError < StandardError; end

      attr_reader :url

      def initialize(url: nil, api_key: nil, username: nil, password: nil, space_id: nil)
        @url = url || ENV["DIFFDASH_KIBANA_URL"] || raise(Error, "DIFFDASH_KIBANA_URL not set")
        @api_key = api_key || ENV["DIFFDASH_KIBANA_API_KEY"]
        @username = username || ENV["DIFFDASH_KIBANA_USERNAME"]
        @password = password || ENV["DIFFDASH_KIBANA_PASSWORD"]
        @space_id = space_id || ENV["DIFFDASH_KIBANA_SPACE_ID"] || "default"
        
        unless @api_key || (@username && @password)
          raise Error, "DIFFDASH_KIBANA_API_KEY or DIFFDASH_KIBANA_USERNAME/PASSWORD required"
        end
      end

      # Validates connection to Kibana
      # Tries multiple endpoints since Elastic Cloud Serverless uses different paths
      def health_check!
        # Try endpoints in order of preference
        endpoints = [
          "/api/status",                    # Standard Kibana
          "/api/saved_objects/_find?type=dashboard&per_page=1"  # Elastic Cloud Serverless
        ]

        last_error = nil
        endpoints.each do |endpoint|
          response = connection.get(endpoint)
          
          if response.success?
            return true
          elsif response.status == 401
            raise ConnectionError, "Kibana authentication failed (401): Check your credentials"
          else
            last_error = "#{response.status}: #{response.body}"
          end
        end

        raise ConnectionError, "Kibana health check failed (#{last_error})"
      rescue Faraday::Error => e
        raise ConnectionError, "Cannot connect to Kibana at #{@url}: #{e.message}"
      end

      # Import saved objects (dashboard, visualizations, index patterns)
      # @param ndjson_content [String] NDJSON formatted saved objects
      # @return [Hash] Import result with :success, :errors
      def import_saved_objects(ndjson_content)
        endpoint = if @space_id && @space_id != "default"
                     "/s/#{@space_id}/api/saved_objects/_import"
                   else
                     "/api/saved_objects/_import"
                   end

        response = connection.post(endpoint) do |req|
          req.params["overwrite"] = "true"
          req.headers["Content-Type"] = "multipart/form-data"
          req.headers["kbn-xsrf"] = "true"
          
          # Kibana expects the NDJSON as a file upload
          req.body = {
            file: Faraday::Multipart::FilePart.new(
              StringIO.new(ndjson_content),
              "application/ndjson",
              "dashboard.ndjson"
            )
          }
        end

        unless response.success?
          body = JSON.parse(response.body) rescue { "message" => response.body }
          error_msg = body["message"] || body["error"] || "Unknown error"
          raise Error, "Kibana API error (#{response.status}): #{error_msg}"
        end

        result = JSON.parse(response.body)
        
        # Extract dashboard URL from successful import
        dashboard_id = extract_dashboard_id(result)
        dashboard_url = dashboard_id ? build_dashboard_url(dashboard_id) : nil
        
        {
          success: result["success"],
          successCount: result["successCount"],
          errors: result["errors"] || [],
          url: dashboard_url
        }
      end

      # List existing dashboards
      def list_dashboards
        response = connection.get("/api/saved_objects/_find") do |req|
          req.params["type"] = "dashboard"
          req.params["per_page"] = 100
        end

        unless response.success?
          raise Error, "Failed to list dashboards: #{response.body}"
        end

        result = JSON.parse(response.body)
        result["saved_objects"] || []
      end

      private

      def connection
        @connection ||= Faraday.new(url: @url) do |f|
          f.request :multipart
          f.adapter Faraday.default_adapter
          
          if @api_key
            f.headers["Authorization"] = "ApiKey #{@api_key}"
          elsif @username && @password
            f.request :authorization, :basic, @username, @password
          end
          
          f.headers["Accept"] = "application/json"
        end
      end

      def extract_dashboard_id(import_result)
        return nil unless import_result["successResults"]
        
        dashboard = import_result["successResults"].find { |obj| obj["type"] == "dashboard" }
        dashboard&.dig("id")
      end

      def build_dashboard_url(dashboard_id)
        space_path = @space_id && @space_id != "default" ? "/s/#{@space_id}" : ""
        "#{@url}#{space_path}/app/dashboards#/view/#{dashboard_id}"
      end
    end
  end
end
