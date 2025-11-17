# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline do
  describe "#advance!" do
    subject(:pipeline) do
      create(:pipeline, status: :in_progress, definition: definition)
    end

    context "when the next step is 'collapse'" do
      let(:definition) do
        {
          nodes: %w[MyStepA MyStepB MyStepC],
          edges: {
            "MyStepA" => [{ to: %w[MyStepB], type: "expand" }],
            "MyStepB" => [{ to: %w[MyStepC], type: "collapse" }],
            "MyStepC" => [],
          },
        }.to_json
      end
      let(:step) do
        create(:step, status: :advancing, klass: "MyStepB", pipeline: pipeline)
      end
      let(:output_payload) { { payload: }.to_json }
      let(:payload) { 1 }

      before do
        # other steps from the other branches of the `expand` action
        other_steps = create_list(
          :step,
          2,
          status: :completed,
          klass: "MyStepB",
          pipeline: pipeline
        )
        create(:job, output_payload: output_payload, step: other_steps[0])
        create(:job, output_payload: output_payload, step: other_steps[1])
        create(:job, output_payload:, step:)
      end

      it "creates a new step and enqueues a job" do
        expect do
          pipeline.advance!
        end.to change(Ductwork::Step, :count).by(1)
          .and change(Ductwork::Job, :count).by(1)
        step = Ductwork::Step.last
        expect(step).to be_in_progress
        expect(step.klass).to eq("MyStepC")
        expect(step.step_type).to eq("collapse")
      end

      it "passes the output payload as input arguments to the next step" do
        allow(Ductwork::Job).to receive(:enqueue)

        pipeline.advance!

        expect(Ductwork::Job).to have_received(:enqueue).with(anything, [1, 1, 1])
      end
    end
  end
end
