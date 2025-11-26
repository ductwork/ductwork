# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline, "#advance" do
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

    it "raises if the return value is larger than the max depth config" do
      Ductwork.configuration.steps_max_depth = 2

      expect do
        pipeline.advance!
      end.to raise_error(described_class::StepDepthError)
    end

    context "when the pipeline has been divided" do
      let(:definition) do
        {
          nodes: %w[MyStepA MyStepB MyStepC MyStepD MyStepE],
          edges: {
            "MyStepA" => [{ to: %w[MyStepB MyStepC], type: "divide" }],
            "MyStepB" => [{ to: %w[MyStepD], type: "expand" }],
            "MyStepC" => [{ to: %w[MyStepE], type: "expand" }],
            "MyStepD" => [],
            "MyStepE" => [],
          },
        }.to_json
      end
      let(:advancing_steps) do
        [
          create(
            :step,
            status: :advancing,
            step_type: "expand",
            klass: "MyStepB",
            pipeline: pipeline
          ),
          create(
            :step,
            status: :advancing,
            step_type: "expand",
            klass: "MyStepC",
            pipeline: pipeline
          ),
        ]
      end

      before do
        step.completed!
        advancing_steps.each do |s|
          create(:job, output_payload: output_payload, step: s)
        end
      end

      it "creates a new step and job for each step in the active branch" do
        expect do
          pipeline.advance!
        end.to change(Ductwork::Step, :count).by(6)
          .and change(Ductwork::Job, :count).by(6)
        klasses = Ductwork::Step.pluck(:klass).last(6)
        expect(klasses).to eq(
          %w[MyStepD MyStepD MyStepD MyStepE MyStepE MyStepE]
        )
      end
    end

    context "when the pipeline has been expanded" do
      let(:definition) do
        {
          nodes: %w[MyStepA MyStepB MyStepC MyStepD],
          edges: {
            "MyStepA" => [{ to: %w[MyStepB], type: "expand" }],
            "MyStepB" => [{ to: %w[MyStepC], type: "expand" }],
            "MyStepC" => [],
          },
        }.to_json
      end
      let(:advancing_steps) do
        create_list(
          :step,
          2,
          status: :advancing,
          step_type: "expand",
          klass: "MyStepB",
          pipeline: pipeline
        )
      end

      before do
        step.completed!
        advancing_steps.each do |s|
          create(:job, output_payload: output_payload, step: s)
        end
      end

      it "creates a new step and job for each step in the active branch" do
        expect do
          pipeline.advance!
        end.to change(Ductwork::Step, :count).by(6)
          .and change(Ductwork::Job, :count).by(6)
        klasses = Ductwork::Step.pluck(:klass).last(6)
        expect(klasses).to eq(
          %w[MyStepC MyStepC MyStepC MyStepC MyStepC MyStepC]
        )
      end
    end
  end
end
