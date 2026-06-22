# frozen_string_literal: true

RSpec.describe Ductwork::Processes::PipelineAdvancerRunner do
  describe "#start_pipeline_advancers" do
    it "creates and starts a pipeline advancer for each pipeline klass" do
      klasses = %w[PipelineA PipelineB]
      advancer = instance_double(
        Ductwork::Processes::PipelineAdvancer,
        start: nil,
        name: nil
      )
      allow(Ductwork::Processes::PipelineAdvancer).to receive(:new).and_return(advancer)
      runner = described_class.new(*klasses)

      runner.send(:start_pipeline_advancers)

      expect(Ductwork::Processes::PipelineAdvancer).to have_received(:new).with("PipelineA", 0)
      expect(Ductwork::Processes::PipelineAdvancer).to have_received(:new).with("PipelineB", 0)
      expect(advancer).to have_received(:start).twice
    end
  end
end
