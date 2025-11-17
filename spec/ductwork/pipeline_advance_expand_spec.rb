# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline do
  describe "#advance!" do
    subject(:pipeline) do
      create(:pipeline, status: :in_progress, definition: definition)
    end

    context "when the next step is 'expand'" do
      let(:definition) do
        {
          nodes: %w[MyStepA MyStepB],
          edges: {
            "MyStepA" => [{ to: %w[MyStepB], type: "expand" }],
            "MyStepB" => [],
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
        end.to change(Ductwork::Step, :count).by(3)
          .and change(Ductwork::Job, :count).by(3)
        steps = Ductwork::Step.last(3)
        expect(steps[0]).to be_in_progress
        expect(steps[0].klass).to eq("MyStepB")
        expect(steps[0].step_type).to eq("expand")
        expect(steps[1]).to be_in_progress
        expect(steps[1].klass).to eq("MyStepB")
        expect(steps[1].step_type).to eq("expand")
        expect(steps[2]).to be_in_progress
        expect(steps[2].klass).to eq("MyStepB")
        expect(steps[2].step_type).to eq("expand")
      end

      it "passes the output payload as input arguments to the next step" do
        allow(Ductwork::Job).to receive(:enqueue)

        pipeline.advance!

        expect(Ductwork::Job).to have_received(:enqueue).with(anything, "a")
        expect(Ductwork::Job).to have_received(:enqueue).with(anything, "b")
        expect(Ductwork::Job).to have_received(:enqueue).with(anything, "c")
      end
    end
  end
end
