# frozen_string_literal: true

RSpec.describe Ductwork::Processes::ProcessSupervisorRunner do
  describe "#run" do
    it "creates workers for each configured pipeline" do
      pipelines = %w[PipelineA PipelineB]
      supervisor = instance_double(
        Ductwork::Processes::ProcessSupervisor,
        add_worker: nil,
        run: nil
      )
      allow(Ductwork::Processes::ProcessSupervisor).to receive(:new).and_return(supervisor)

      described_class.new(*pipelines).run

      expect(Ductwork::Processes::ProcessSupervisor).to have_received(:new)
      expect(supervisor).to have_received(:add_worker)
        .with({ metadata: { pipelines: %w[PipelineA PipelineB] } }).once
      expect(supervisor).to have_received(:run)
    end
  end
end
