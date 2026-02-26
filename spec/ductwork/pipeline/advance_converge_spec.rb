# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline, "#advance!" do
  subject(:pipeline) do
    create(:pipeline, status: :in_progress, definition: definition)
  end

  context "when the next step is 'converge'" do
    let(:definition) do
      {
        nodes: %w[MyStepA.0 MyStepB.1 MyStepC.2 MyStepD.3],
        edges: {
          "MyStepA.0" => {
            to: { "bar" => "MyStepB.1", "otherwise" => "MyStepC.2" },
            type: "divert",
            klass: "MyStepA",
          },
          "MyStepB.1" => { to: %w[MyStepD.3], type: "converge", klass: "MyStepB" },
          "MyStepC.2" => { to: %w[MyStepD.3], type: "converge", klass: "MyStepC" },
          "MyStepD.3" => { klass: "MyStepD" },
        },
      }.to_json
    end
    let(:step) do
      create(
        :step,
        status: :advancing,
        node: "MyStepB.1",
        klass: "MyStepB",
        pipeline: pipeline
      )
    end

    it "creates a new step and enqueues a job" do
      create(:job, output_payload: { payload: "result" }.to_json, step: step)

      expect do
        pipeline.advance!
      end.to change(Ductwork::Step, :count).by(1)
        .and change(Ductwork::Job, :count).by(1)

      new_step = Ductwork::Step.last
      expect(new_step).to be_in_progress
      expect(new_step.node).to eq("MyStepD.3")
      expect(new_step.klass).to eq("MyStepD")
      expect(new_step.to_transition).to eq("converge")
    end

    it "passes the return value as input to the next step" do
      create(:job, output_payload: { payload: "result" }.to_json, step: step)
      allow(Ductwork::Job).to receive(:enqueue)

      pipeline.advance!

      expect(Ductwork::Job).to have_received(:enqueue).with(anything, "result")
    end
  end
end
