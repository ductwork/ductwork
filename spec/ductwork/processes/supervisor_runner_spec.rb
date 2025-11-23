# frozen_string_literal: true

RSpec.describe Ductwork::Processes::SupervisorRunner do
  describe ".start!" do
    it "creates workers for each configured pipeline" do
      Ductwork.logger = spy
      Ductwork.configuration = instance_double(
        Ductwork::Configuration,
        pipelines: %w[PipelineA PipelineB]
      )
      supervisor = instance_double(
        Ductwork::Processes::Supervisor,
        add_worker: nil,
        run: nil
      )
      allow(Ductwork::Processes::Supervisor).to receive(:new).and_return(supervisor)

      described_class.start!

      expect(Ductwork::Processes::Supervisor).to have_received(:new)
      expect(supervisor).to have_received(:add_worker)
        .with({ metadata: { pipelines: %w[PipelineA PipelineB] } }).once
      expect(supervisor).to have_received(:run)
    end
  end
end
