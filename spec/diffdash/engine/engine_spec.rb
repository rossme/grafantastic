# frozen_string_literal: true

RSpec.describe Diffdash::Engine::Engine do
  let(:config) { Diffdash::Config.new }
  let(:collector) { instance_double(Diffdash::Services::SignalCollector) }
  let(:validator) { instance_double(Diffdash::Validation::Limits, truncate_and_validate: [log_signal, counter_signal], warnings: []) }
  let(:change_set) do
    Diffdash::Engine::ChangeSet.new(
      branch_name: "feature/test",
      changed_files: ["app/models/user.rb"],
      filtered_files: ["app/models/user.rb"]
    )
  end

  let(:log_signal) do
    Diffdash::Signal::Log.new(
      name: "user_created",
      source_file: "app/models/user.rb",
      defining_class: "User",
      inheritance_depth: 0,
      metadata: { level: "info" }
    )
  end

  let(:counter_signal) do
    Diffdash::Signal::Counter.new(
      name: "users_created_total",
      source_file: "app/models/user.rb",
      defining_class: "User",
      inheritance_depth: 0,
      metadata: { metric_type: :counter }
    )
  end

  before do
    allow(Diffdash::Services::SignalCollector).to receive(:new).and_return(collector)
    allow(Diffdash::Validation::Limits).to receive(:new).and_return(validator)
    allow(collector).to receive(:collect).and_return([log_signal, counter_signal])
    allow(collector).to receive(:dynamic_metrics).and_return([{ file: "app/models/user.rb", line: 10 }])
  end

  it "returns a SignalBundle with logs and metrics" do
    bundle = described_class.new(config: config).run(change_set: change_set)

    expect(bundle.logs.size).to eq(1)
    expect(bundle.metrics.size).to eq(1)
    expect(bundle.logs.first.type).to eq(:logs)
    expect(bundle.metrics.first.type).to eq(:metrics)
  end

  it "includes change set and dynamic metrics metadata" do
    bundle = described_class.new(config: config).run(change_set: change_set)

    expect(bundle.metadata[:change_set][:branch_name]).to eq("feature/test")
    expect(bundle.metadata[:dynamic_metrics]).to eq([{ file: "app/models/user.rb", line: 10 }])
  end

  it "truncates signals if limits exceeded" do
    described_class.new(config: config).run(change_set: change_set)

    expect(validator).to have_received(:truncate_and_validate).with([log_signal, counter_signal])
  end
end
