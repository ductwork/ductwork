# frozen_string_literal: true

RSpec.describe Ductwork::Processes::ThreadSupervisorRunner do
  describe "#run" do
    it "creates pipeline advancer and job worker workers" do
      pipelines = %w[PipelineA PipelineB]
      supervisor = instance_double(
        Ductwork::Processes::ThreadSupervisor,
        add_worker: nil,
        run: nil
      )
      allow(Ductwork::Processes::ThreadSupervisor).to receive(:new).and_return(supervisor)

      described_class.new(*pipelines).run

      expect(Ductwork::Processes::ThreadSupervisor).to have_received(:new)
      expect(supervisor).to have_received(:add_worker)
        .with({ metadata: { pipeline: "PipelineA" } })
        .exactly(6).times
      expect(supervisor).to have_received(:add_worker)
        .with({ metadata: { pipeline: "PipelineB" } })
        .exactly(6).times
      expect(supervisor).to have_received(:run)
    end
  end
end
