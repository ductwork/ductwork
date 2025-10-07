# frozen_string_literal: true

RSpec.describe Ductwork::WorkerLauncher do
  describe ".start!" do
    it "creates workers for each configured pipeline" do
      pipelines = %w[PipelineA PipelineB]
      Ductwork.configuration = instance_double(Ductwork::Configuration, pipelines:)
      supervisor = instance_double(Ductwork::Supervisor, add_worker: nil, run: nil)
      allow(Ductwork::Supervisor).to receive(:new).and_return(supervisor)

      described_class.start!

      expect(Ductwork::Supervisor).to have_received(:new)
      expect(supervisor).to have_received(:add_worker)
        .with({ metadata: { pipeline: /Pipeline./ } }).twice
      expect(supervisor).to have_received(:run)
    end
  end
end
