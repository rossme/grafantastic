# frozen_string_literal: true

RSpec.describe Diffdash::CLI::Runner do
  let(:config) { instance_double(Diffdash::Config, grafana_folder_id: nil) }
  let(:change_set) do
    Diffdash::Engine::ChangeSet.new(
      branch_name: 'feature/test',
      changed_files: ['app/models/user.rb'],
      filtered_files: ['app/models/user.rb']
    )
  end
  let(:bundle) do
    Diffdash::Engine::SignalBundle.new(
      logs: [
        Diffdash::Engine::SignalQuery.new(
          type: :logs,
          name: 'hello',
          time_range: { from: 'now-30m', to: 'now' }
        )
      ],
      metrics: [],
      traces: [],
      metadata: { change_set: change_set.to_h, time_range: { from: 'now-30m', to: 'now' } }
    )
  end

  let(:good_adapter) do
    Class.new(Diffdash::Outputs::Base) do
      def render(_bundle)
        { ok: true }
      end
    end.new
  end

  let(:bad_adapter) do
    Class.new(Diffdash::Outputs::Base) do
      def render(_bundle)
        raise 'boom'
      end
    end.new
  end

  subject(:runner) { described_class.new([]) }

  before do
    allow(Diffdash::Config).to receive(:new).and_return(config)
    allow(Diffdash::Engine::ChangeSet).to receive(:from_git).and_return(change_set)
    allow(Diffdash::Engine::Engine).to receive(:new).and_return(instance_double(Diffdash::Engine::Engine, run: bundle))
  end

  it 'continues when one adapter fails' do
    allow(runner).to receive(:build_outputs).and_return([bad_adapter, good_adapter])

    results, errors = runner.send(:run_outputs, [bad_adapter, good_adapter], bundle)

    expect(errors.size).to eq(1)
    expect(results.values.map { |r| r[:payload] }).to include({ ok: true })
  end

  describe '--version flag' do
    it 'prints version and exits with 0' do
      runner = described_class.new(['--version'])

      expect { runner.execute }.to output("diffdash #{Diffdash::VERSION}\n").to_stdout
    end

    it 'returns exit code 0' do
      runner = described_class.new(['--version'])

      expect(runner.execute).to eq(0)
    end

    it 'bypasses argument validation like --help' do
      runner = described_class.new(['--version', '--invalid-arg'])

      expect { runner.execute }.to output("diffdash #{Diffdash::VERSION}\n").to_stdout
      expect(runner.execute).to eq(0)
    end
  end
end
