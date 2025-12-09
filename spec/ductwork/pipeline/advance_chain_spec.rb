# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline, "#advance!" do
  subject(:pipeline) do
    create(:pipeline, status: :in_progress, definition: definition)
  end

  context "when the next step is 'chain'" do
    let(:definition) do
      {
        nodes: %w[MyStepA MyStepB],
        edges: {
          "MyStepA" => [{ to: %w[MyStepB], type: "chain" }],
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
      end.to change(Ductwork::Step, :count).by(1)
        .and change(Ductwork::Job, :count).by(1)
      step = Ductwork::Step.last
      expect(step).to be_in_progress
      expect(step.klass).to eq("MyStepB")
      expect(step.to_transition).to eq("default")
    end

    it "passes the output payload as input arguments to the next step" do
      allow(Ductwork::Job).to receive(:enqueue)

      pipeline.advance!

      expect(Ductwork::Job).to have_received(:enqueue).with(anything, payload)
    end

    context "when the pipeline has been divided" do
      let(:advancing_steps) do
        [
          create(
            :step,
            status: :advancing,
            to_transition: :default,
            klass: "MyStepB",
            pipeline: pipeline
          ),
          create(
            :step,
            status: :advancing,
            to_transition: :default,
            klass: "MyStepC",
            pipeline: pipeline
          ),
        ]
      end
      let(:definition) do
        {
          nodes: %w[MyStepA MyStepB MyStepC MyStepD],
          edges: {
            "MyStepA" => [{ to: %w[MyStepB MyStepC], type: "divide" }],
            "MyStepB" => [{ to: %w[MyStepD], type: "chain" }],
            "MyStepC" => [{ to: %w[MyStepD], type: "chain" }],
            "MyStepD" => [],
          },
        }.to_json
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
        end.to change(Ductwork::Step, :count).by(2)
          .and change(Ductwork::Job, :count).by(2)
        klasses = Ductwork::Step.pluck(:klass).last(2)
        expect(klasses).to eq(%w[MyStepD MyStepD])
      end
    end

    context "when the pipeline has been expanded" do
      let(:advancing_steps) do
        create_list(
          :step,
          2,
          status: :advancing,
          to_transition: :default,
          klass: "MyStepB",
          pipeline: pipeline
        )
      end
      let(:definition) do
        {
          nodes: %w[MyStepA MyStepB MyStepC],
          edges: {
            "MyStepA" => [{ to: %w[MyStepB], type: "expand" }],
            "MyStepB" => [{ to: %w[MyStepC], type: "chain" }],
            "MyStepC" => [],
          },
        }.to_json
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
        end.to change(Ductwork::Step, :count).by(2)
          .and change(Ductwork::Job, :count).by(2)
        klasses = Ductwork::Step.pluck(:klass).last(2)
        expect(klasses).to eq(%w[MyStepC MyStepC])
      end
    end
  end
end
