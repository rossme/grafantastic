# frozen_string_literal: true

require "json"

RSpec.describe "Grafana v1 dashboard contract" do
  let(:fixture_path) { File.join(__dir__, "../../fixtures/grafana/dashboard_v1_fixture.json") }

  def stringify_keys(value)
    case value
    when Hash
      value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = stringify_keys(v) }
    when Array
      value.map { |item| stringify_keys(item) }
    else
      value
    end
  end

  it "matches the golden dashboard fixture" do
    signal = Diffdash::Engine::SignalQuery.new(
      type: :logs,
      name: "hello_from_grape_api",
      time_range: { from: "now-1h", to: "now" },
      source_file: "/app/api/v1/base.rb",
      defining_class: "V1::Base",
      metadata: { level: "info", line: 42 }
    )
    bundle = Diffdash::Engine::SignalBundle.new(
      logs: [signal],
      metrics: [],
      traces: [],
      metadata: {
        time_range: { from: "now-1h", to: "now" },
        change_set: { branch_name: "contract-dashboard" }
      }
    )
    renderer = Diffdash::Outputs::Grafana.new(
      title: "contract-dashboard",
      folder_id: 123
    )

    output = stringify_keys(renderer.render(bundle))
    fixture = JSON.parse(File.read(fixture_path))

    expect(output).to eq(fixture)
  end
end
