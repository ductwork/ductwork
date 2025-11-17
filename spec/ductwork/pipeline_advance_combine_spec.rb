# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline do
  describe "#advance!" do
    subject(:pipeline) do
      create(:pipeline, status: :in_progress, definition: definition)
    end

    context "when the next step is 'combine'" do
      let(:definition) do
        {
          nodes: %w[MyStepA MyStepB MyStepC MyStepD],
          edges: {
            "MyStepA" => [{ to: %w[MyStepB MyStepC], type: "divide" }],
            "MyStepB" => [{ to: %w[MyStepD], type: "combine" }],
            "MyStepC" => [{ to: %w[MyStepD], type: "combine" }],
            "MyStepD" => [],
          },
        }.to_json
      end
      let(:step) do
        create(:step, status: :advancing, klass: "MyStepC", pipeline: pipeline)
      end
      let(:output_payload) { { payload: }.to_json }
      let(:payload) { %w[a b c] }

      before do
        # other step from the other branch of the `divide` action
        other_step = create(
          :step,
          status: :completed,
          klass: "MyStepB",
          pipeline: pipeline
        )
        create(:job, output_payload: output_payload, step: other_step)
        create(:job, output_payload:, step:)
      end

      it "creates a new step and enqueues a job" do
        expect do
          pipeline.advance!
        end.to change(Ductwork::Step, :count).by(1)
          .and change(Ductwork::Job, :count).by(1)
        step = Ductwork::Step.last
        expect(step).to be_in_progress
        expect(step.klass).to eq("MyStepD")
        expect(step.step_type).to eq("combine")
      end

      it "passes the output payload as input arguments to the next step" do
        allow(Ductwork::Job).to receive(:enqueue)

        pipeline.advance!

        expect(Ductwork::Job).to have_received(:enqueue).with(
          anything, [payload, payload]
        )
      end
    end
  end
end
