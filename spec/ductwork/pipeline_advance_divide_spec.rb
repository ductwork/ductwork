# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline do
  describe "#advance!" do
    subject(:pipeline) do
      create(:pipeline, status: :in_progress, definition: definition)
    end

    context "when the next step is 'divide'" do
      let(:definition) do
        {
          nodes: %w[MyStepA MyStepB MyStepC],
          edges: {
            "MyStepA" => [{ to: %w[MyStepB MyStepC], type: "divide" }],
            "MyStepB" => [],
            "MyStepC" => [],
          },
        }.to_json
      end
      let(:step) do
        create(:step, status: :advancing, klass: "MyStepA", pipeline: pipeline)
      end
      let(:output_payload) { { payload: }.to_json }
      let(:payload) { %w[a b c] }

      before do
        create(:job, output_payload:, step:)
      end

      it "creates a new step and enqueues a job" do
        expect do
          pipeline.advance!
        end.to change(Ductwork::Step, :count).by(2)
          .and change(Ductwork::Job, :count).by(2)
        steps = Ductwork::Step.last(2)
        expect(steps.first).to be_in_progress
        expect(steps.first.klass).to eq("MyStepB")
        expect(steps.first.step_type).to eq("divide")
        expect(steps.last).to be_in_progress
        expect(steps.last.klass).to eq("MyStepC")
        expect(steps.last.step_type).to eq("divide")
      end

      it "passes the output payload as input arguments to the next step" do
        allow(Ductwork::Job).to receive(:enqueue)

        pipeline.advance!

        expect(Ductwork::Job).to have_received(:enqueue).with(anything, payload).twice
      end
    end
  end
end
