# frozen_string_literal: true

RSpec.describe Ductwork::Processes::PipelineAdvancer do
  describe "#call" do
    subject(:advancer) { described_class.new(running_context, *klasses) }

    let(:running_context) { Ductwork::RunningContext.new }
    let(:klasses) { %w[MyPipeline1] }
    let(:pipeline) { create(:pipeline, status: :in_progress, definition: definition) }
    let(:definition) { {}.to_json }

    it "completes steps in 'advancing' status" do
      advancing_step = create(:step, status: :advancing)
      in_progress_step = create(:step, status: :in_progress)

      expect do
        advancer.call
      end.to change { advancing_step.reload.status }.to("completed")
        .and(change { advancing_step.completed_at }.from(nil))
        .and(not_change { in_progress_step.reload.status })
    end

    it "only updates steps for the configured pipelines" do
      other_pipeline = create(:pipeline, klass: "OtherPipeline")
      skipped_step = create(:step, status: :advancing, pipeline: other_pipeline)

      expect do
        advancer.call
      end.not_to(change { skipped_step.reload.status })
    end

    it "no-ops if the running context is shutdown" do
      step = create(:step, status: :advancing)
      running_context.shutdown!

      expect do
        advancer.call
      end.not_to(change { step.reload.status })
    end

    it "does not mark the pipeline as complete if some steps not completed" do
      create(:step, status: :in_progress, pipeline: pipeline)

      expect do
        advancer.call
      end.not_to(change { pipeline.reload.status })
    end

    it "marks the pipeline as complete if all steps are completed" do
      create(:step, status: :advancing, pipeline: pipeline)

      expect do
        advancer.call
      end.to change { pipeline.reload.status }.from("in_progress").to("completed")
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
          advancer.call
        end.to change(Ductwork::Step, :count).by(1)
          .and change(Ductwork::Job, :count).by(1)
        step = Ductwork::Step.last
        expect(step).to be_in_progress
        expect(step.klass).to eq("MyStepB")
        expect(step.step_type).to eq("default")
      end

      it "passes the output payload as input arguments to the next step" do
        allow(Ductwork::Job).to receive(:enqueue)

        advancer.call

        expect(Ductwork::Job).to have_received(:enqueue).with(anything, payload)
      end
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
          advancer.call
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

        advancer.call

        expect(Ductwork::Job).to have_received(:enqueue).with(anything, payload).twice
      end
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
          advancer.call
        end.to change(Ductwork::Step, :count).by(1)
          .and change(Ductwork::Job, :count).by(1)
        step = Ductwork::Step.last
        expect(step).to be_in_progress
        expect(step.klass).to eq("MyStepD")
        expect(step.step_type).to eq("combine")
      end

      it "passes the output payload as input arguments to the next step" do
        allow(Ductwork::Job).to receive(:enqueue)

        advancer.call

        expect(Ductwork::Job).to have_received(:enqueue).with(
          anything, [payload, payload]
        )
      end
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
          advancer.call
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

        advancer.call

        expect(Ductwork::Job).to have_received(:enqueue).with(anything, "a")
        expect(Ductwork::Job).to have_received(:enqueue).with(anything, "b")
        expect(Ductwork::Job).to have_received(:enqueue).with(anything, "c")
      end
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
          advancer.call
        end.to change(Ductwork::Step, :count).by(1)
          .and change(Ductwork::Job, :count).by(1)
        step = Ductwork::Step.last
        expect(step).to be_in_progress
        expect(step.klass).to eq("MyStepC")
        expect(step.step_type).to eq("collapse")
      end

      it "passes the output payload as input arguments to the next step" do
        allow(Ductwork::Job).to receive(:enqueue)

        advancer.call

        expect(Ductwork::Job).to have_received(:enqueue).with(anything, [1, 1, 1])
      end
    end
  end
end
