# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline, "#advance!" do
  subject(:pipeline) do
    create(:pipeline, status: :in_progress, definition: definition)
  end

  context "when the next step is 'divert'" do
    let(:definition) do
      {
        nodes: %w[MyStepA.0 MyStepB.1 MyStepC.2 MyStepD.3],
        edges: {
          "MyStepA.0" => {
            to: { "bar" => "MyStepB.1", "baz" => "MyStepC.2", "otherwise" => "MyStepD.3" },
            type: "divert",
            klass: "MyStepA",
          },
          "MyStepB.1" => { klass: "MyStepB" },
          "MyStepC.2" => { klass: "MyStepC" },
          "MyStepD.3" => { klass: "MyStepD" },
        },
      }.to_json
    end
    let(:step) do
      create(
        :step,
        status: :advancing,
        node: "MyStepA.0",
        klass: "MyStepA",
        pipeline: pipeline
      )
    end

    it "routes to the correct step when return value matches a key" do
      create(:job, output_payload: { payload: "bar" }.to_json, step: step)

      expect do
        pipeline.advance!
      end.to change(Ductwork::Step, :count).by(1)
        .and change(Ductwork::Job, :count).by(1)

      new_step = Ductwork::Step.last
      expect(new_step).to be_in_progress
      expect(new_step.node).to eq("MyStepB.1")
      expect(new_step.klass).to eq("MyStepB")
      expect(new_step.to_transition).to eq("divert")
    end

    it "routes to otherwise when return value doesn't match any key" do
      create(:job, output_payload: { payload: "unknown" }.to_json, step: step)

      expect do
        pipeline.advance!
      end.to change(Ductwork::Step, :count).by(1)
        .and change(Ductwork::Job, :count).by(1)

      new_step = Ductwork::Step.last
      expect(new_step).to be_in_progress
      expect(new_step.node).to eq("MyStepD.3")
      expect(new_step.klass).to eq("MyStepD")
    end

    it "passes return value as input to the next step" do
      create(:job, output_payload: { payload: "baz" }.to_json, step: step)
      allow(Ductwork::Job).to receive(:enqueue)

      pipeline.advance!

      expect(Ductwork::Job).to have_received(:enqueue).with(anything, "baz")
    end

    context "when there is no match and no otherwise branch" do
      let(:definition) do
        {
          nodes: %w[MyStepA.0 MyStepB.1],
          edges: {
            "MyStepA.0" => {
              to: { "bar" => "MyStepB.1" },
              type: "divert",
              klass: "MyStepA",
            },
            "MyStepB.1" => { klass: "MyStepB" },
          },
        }.to_json
      end

      it "halts the pipeline" do
        create(:job, output_payload: { payload: "unknown" }.to_json, step: step)

        expect do
          pipeline.advance!
        end.not_to change(Ductwork::Step, :count)

        expect(pipeline.reload).to be_halted
      end
    end
  end
end
