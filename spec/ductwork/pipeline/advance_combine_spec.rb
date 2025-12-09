# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline, "#advance" do
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
        status: :advancing,
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
      expect(step.to_transition).to eq("combine")
    end

    it "passes the output payload as input arguments to the next step" do
      allow(Ductwork::Job).to receive(:enqueue)

      pipeline.advance!

      expect(Ductwork::Job).to have_received(:enqueue).with(
        anything, [payload, payload]
      )
    end

    context "when the pipeline has been expanded then divided" do
      let(:advancing_steps) do
        [
          *create_list(
            :step,
            3,
            status: :advancing,
            to_transition: :combine,
            klass: "MyStepC",
            pipeline: pipeline
          ),
          *create_list(
            :step,
            3,
            status: :advancing,
            to_transition: :combine,
            klass: "MyStepD",
            pipeline: pipeline
          ),
          *create_list(
            :step,
            3,
            status: :advancing,
            to_transition: :combine,
            klass: "MyStepE",
            pipeline: pipeline
          ),
        ]
      end
      let(:definition) do
        {
          nodes: %w[MyStepA MyStepB MyStepC MyStepD MyStepE MyStepF],
          edges: {
            "MyStepA" => [{ to: %w[MyStepB], type: "expand" }],
            "MyStepB" => [{ to: %w[MyStepC MyStepD MyStepE], type: "divide" }],
            "MyStepC" => [{ to: %w[MyStepF], type: "combine" }],
            "MyStepD" => [{ to: %w[MyStepF], type: "combine" }],
            "MyStepE" => [{ to: %w[MyStepF], type: "combine" }],
            "MyStepF" => [],
          },
        }.to_json
      end

      before do
        # assume all previous steps have completed successfully
        Ductwork::Step.update!(status: "completed")
        advancing_steps.each do |s|
          create(:job, output_payload: output_payload, step: s)
        end
      end

      it "collapses each active branch" do
        expect do
          pipeline.advance!
        end.to change(Ductwork::Step, :count).by(3)
          .and change(Ductwork::Job, :count).by(3)
        klasses = Ductwork::Step.pluck(:klass).last(3)
        expect(klasses).to eq(%w[MyStepF MyStepF MyStepF])
      end
    end
  end
end
