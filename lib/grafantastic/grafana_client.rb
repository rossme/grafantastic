# frozen_string_literal: true

require "faraday"
require "json"

module Grafantastic
  class GrafanaClient
    class ConnectionError < StandardError; end

    attr_reader :url

    def initialize
      @url = ENV.fetch("GRAFANA_URL") { raise Error, "GRAFANA_URL not set" }
      @token = ENV.fetch("GRAFANA_TOKEN") { raise Error, "GRAFANA_TOKEN not set" }
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
