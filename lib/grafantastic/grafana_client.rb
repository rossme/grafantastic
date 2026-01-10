# frozen_string_literal: true

require "faraday"
require "json"

module Grafantastic
  class GrafanaClient
    class ConnectionError < StandardError; end

    attr_reader :url

    # Initialize with explicit url/token or fall back to ENV
    def initialize(url: nil, token: nil)
      @url = url || ENV.fetch("GRAFANA_URL") { raise Error, "GRAFANA_URL not set" }
      @token = token || ENV.fetch("GRAFANA_TOKEN") { raise Error, "GRAFANA_TOKEN not set" }
    end

    # Validates connection to Grafana by hitting the health endpoint
    # Raises ConnectionError if connection fails or returns non-200
    def health_check!
      response = connection.get("/api/health")

      unless response.success?
        raise ConnectionError, "Grafana health check failed (#{response.status}): #{response.body}"
      end

      true
    rescue Faraday::Error => e
      raise ConnectionError, "Cannot connect to Grafana at #{@url}: #{e.message}"
    end

    def upload(dashboard_payload)
      response = connection.post("/api/dashboards/db") do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = JSON.generate(dashboard_payload)
      end

      unless response.success?
        body = JSON.parse(response.body) rescue { "message" => response.body }
        raise Error, "Grafana API error (#{response.status}): #{body["message"]}"
      end

      result = JSON.parse(response.body)
      {
        id: result["id"],
        uid: result["uid"],
        url: "#{@url}#{result["url"]}",
        status: result["status"]
      }
    end

    # List all folders the API token has access to
    def list_folders
      response = connection.get("/api/folders")

      unless response.success?
        body = JSON.parse(response.body) rescue { "message" => response.body }
        raise ConnectionError, "Failed to list folders (#{response.status}): #{body["message"]}"
      end

      JSON.parse(response.body)
    rescue Faraday::Error => e
      raise ConnectionError, "Cannot connect to Grafana at #{@url}: #{e.message}"
    end

    private

    def connection
      @connection ||= Faraday.new(url: @url) do |f|
        f.adapter Faraday.default_adapter
        f.headers["Authorization"] = "Bearer #{@token}"
        f.headers["Accept"] = "application/json"
      end
    end
  end
end
