# frozen_string_literal: true

RSpec.describe Ductwork::Processes::ThreadSupervisor, :no_transaction do
  subject(:supervisor) { described_class.new }

  let(:block) { ->(_supervisor) {} }
  let(:pipeline) { "MyPipeline" }

  describe "#initialize" do
    it "calls the supervisor start lifecycle hooks" do
      allow(block).to receive(:call).and_call_original
      Ductwork.on_supervisor_start(&block)

      supervisor = described_class.new

      expect(block).to have_received(:call).with(supervisor)
    end
  end

  describe "#add_worker" do
    it "starts new workers" do
      supervisor.add_worker { Ductwork::Processes::PipelineAdvancer.new(pipeline) }
      supervisor.add_worker { Ductwork::Processes::JobWorker.new(pipeline, 1) }

      expect(supervisor.workers.count).to eq(2)
      expect(supervisor.workers).to all(be_alive)
    ensure
      # NOTE: in an `ensure` so a failed expectation above still tears the
      # threads down instead of leaking them into the next example
      kill_workers(supervisor.workers)
    end
  end
end
