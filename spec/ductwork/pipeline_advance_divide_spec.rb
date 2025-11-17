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

      context "when the pipeline has been expanded" do
        let(:definition) do
          {
            nodes: %w[MyStepA MyStepB MyStepC MyStepD],
            edges: {
              "MyStepA" => [{ to: %w[MyStepB], type: "expand" }],
              "MyStepB" => [{ to: %w[MyStepC MyStepD], type: "divide" }],
              "MyStepC" => [],
              "MyStepD" => [],
            },
          }.to_json
        end
        let(:advancing_steps) do
          create_list(
            :step,
            2,
            status: :advancing,
            step_type: "divide",
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
          end.to change(Ductwork::Step, :count).by(4)
            .and change(Ductwork::Job, :count).by(4)
          klasses = Ductwork::Step.pluck(:klass).last(4)
          expect(klasses).to eq(%w[MyStepC MyStepD MyStepC MyStepD])
        end
      end

      context "when the pipeline has been divided" do
        let(:definition) do
          {
            nodes: %w[MyStepA MyStepB MyStepC MyStepD MyStepE],
            edges: {
              "MyStepA" => [{ to: %w[MyStepB MyStepC], type: "divide" }],
              "MyStepB" => [{ to: %w[MyStepD MyStepE], type: "divide" }],
              "MyStepC" => [{ to: %w[MyStepD MyStepE], type: "divide" }],
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
              step_type: "divide",
              klass: "MyStepB",
              pipeline: pipeline
            ),
            create(
              :step,
              status: :advancing,
              step_type: "divide",
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
          end.to change(Ductwork::Step, :count).by(4)
            .and change(Ductwork::Job, :count).by(4)
          klasses = Ductwork::Step.pluck(:klass).last(4)
          expect(klasses).to eq(%w[MyStepD MyStepE MyStepD MyStepE])
        end
      end
    end
  end
end
