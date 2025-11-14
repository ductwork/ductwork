# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline do
  describe "validations" do
    let(:klass) { "MyPipeline" }
    let(:triggered_at) { Time.current }
    let(:last_advanced_at) { Time.current }
    let(:status) { "in_progress" }
    let(:definition) { JSON.dump({}) }
    let(:definition_sha1) { Digest::SHA1.hexdigest(definition) }

    it "is invalid if the `klass` is not present" do
      pipeline = described_class.new(
        triggered_at:,
        last_advanced_at:,
        status:,
        definition:,
        definition_sha1:
      )

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Klass can't be blank"])
    end

    it "is invalid if `triggered_at` is not present" do
      pipeline = described_class.new(
        klass:,
        last_advanced_at:,
        status:,
        definition:,
        definition_sha1:
      )

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Triggered at can't be blank"])
    end

    it "is invalid if `last_advanced_at` is not present" do
      pipeline = described_class.new(
        klass:,
        triggered_at:,
        status:,
        definition:,
        definition_sha1:
      )

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Last advanced at can't be blank"])
    end

    it "is invalid if `status` is not present" do
      pipeline = described_class.new(
        klass:,
        triggered_at:,
        last_advanced_at:,
        definition:,
        definition_sha1:
      )

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Status can't be blank"])
    end

    it "is invalid if `definition` is not present" do
      pipeline = described_class.new(
        klass:,
        triggered_at:,
        last_advanced_at:,
        status:,
        definition_sha1:
      )

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Definition can't be blank"])
    end

    it "is invalid if `definition_sha1` is not present" do
      pipeline = described_class.new(
        klass:,
        triggered_at:,
        last_advanced_at:,
        status:,
        definition:
      )

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Definition sha1 can't be blank"])
    end

    it "is valid otherwise" do
      pipeline = described_class.new(
        klass:,
        triggered_at:,
        last_advanced_at:,
        status:,
        definition:,
        definition_sha1:
      )

      expect(pipeline).to be_valid
    end
  end

  describe "default scope" do
    subject(:klass) do
      Class.new(described_class) do
        def self.name
          "MyPipeline"
        end
      end
    end

    let(:other_pipeline_klass) do
      Class.new(described_class) do
        def self.name
          "MyOtherPipeline"
        end
      end
    end

    it "only returns records with the given pipeline name" do
      record = klass.create!(
        klass: "MyPipeline",
        status: :in_progress,
        definition: "{}",
        definition_sha1: Digest::SHA1.hexdigest("{}"),
        triggered_at: Time.current,
        last_advanced_at: Time.current
      )

      expect(klass.all.count).to eq(1)
      expect(klass.all.first).to eq(record)
      expect(other_pipeline_klass.all.count).to eq(0)
    end
  end

  describe ".define" do
    subject(:klass) do
      Class.new(described_class) do
        def self.name
          "MyPipeline"
        end
      end
    end

    it "raises if no definition block is given" do
      expect do
        klass.define
      end.to raise_error(
        described_class::DefinitionError,
        "Definition block must be given"
      )
    end

    it "raises if a pipeline has already been defined on the class" do
      expect do
        klass.define do |pipeline|
          pipeline.start(spy)
        end

        klass.define do |pipeline|
          pipeline.start(spy)
        end
      end.to raise_error(
        described_class::DefinitionError,
        "Pipeline has already been defined"
      )
    end

    it "yields a definition builder to the block" do
      builder = instance_double(Ductwork::DSL::DefinitionBuilder, complete: nil)
      allow(Ductwork::DSL::DefinitionBuilder).to receive(:new).and_return(builder)

      expect do |block|
        klass.define(&block)
      end.to yield_with_args(builder)
    end

    it "sets the definition on the class" do
      expect do
        klass.define do |pipeline|
          pipeline.start(spy)
        end
      end.to change(klass, :pipeline_definition).from(nil)
    end

    it "adds the pipeline to whole set of pipelines" do
      expect do
        klass.define do |pipeline|
          pipeline.start(spy)
        end
      end.to change(Ductwork.defined_pipelines, :count).by(1)
      expect(Ductwork.defined_pipelines).to eq(["MyPipeline"])
    end
  end

  describe ".trigger" do
    subject(:klass) do
      Class.new(described_class) do
        define do |pipeline|
          pipeline.start(MyFirstStep).chain(MySecondStep)
        end

        def self.name
          "MyPipeline"
        end
      end
    end

    let(:args) { 1 }

    it "creates and returns a pipeline record" do
      pipeline = nil

      expect do
        pipeline = klass.trigger(args)
      end.to change(described_class, :count).by(1)
      expect(pipeline.klass).to eq("MyPipeline")
      expect(pipeline).to be_in_progress
      expect(pipeline.definition).to be_present
      expect(pipeline.triggered_at).to be_present
      expect(pipeline.completed_at).to be_nil
    end

    it "creates the initial step record" do
      pipeline = nil

      expect do
        pipeline = klass.trigger(args)
      end.to change(Ductwork::Step, :count).by(1)
      step = pipeline.steps.reload.first
      expect(step).to be_start
      expect(step.klass).to eq("MyFirstStep")
      expect(step.started_at).to be_present
    end

    it "enqueues a job" do
      expect do
        klass.trigger(args)
      end.to change(Ductwork::Job, :count).by(1)
        .and change(Ductwork::Execution, :count).by(1)
        .and change(Ductwork::Availability, :count).by(1)
    end

    it "correctly passes an argument to the job" do
      allow(Ductwork::Job).to receive(:enqueue)

      klass.trigger(1)

      expect(Ductwork::Job).to have_received(:enqueue).with(anything, 1)
    end

    it "correctly passes multiple arguments to the job" do
      allow(Ductwork::Job).to receive(:enqueue)

      klass.trigger(1, 2)

      expect(Ductwork::Job).to have_received(:enqueue).with(anything, 1, 2)
    end

    it "correctly passes an array argument to the job" do
      allow(Ductwork::Job).to receive(:enqueue)

      klass.trigger([1, 2])

      expect(Ductwork::Job).to have_received(:enqueue).with(anything, [1, 2])
    end

    it "raises if pipeline not defined" do
      other_klass = Class.new(described_class) do
        def self.name
          "MyPipeline"
        end
      end

      expect do
        other_klass.trigger(1)
      end.to raise_error(
        described_class::DefinitionError,
        "Pipeline must be defined before triggering"
      )
    end
  end

  describe "#advance!" do
    subject(:pipeline) do
      create(:pipeline, status: :in_progress, definition: definition)
    end

    let(:definition) { {}.to_json }

    it "completes steps in 'advancing' status" do
      advancing_step = create(:step, status: :advancing, pipeline: pipeline)
      in_progress_step = create(:step, status: :in_progress, pipeline: pipeline)

      expect do
        pipeline.advance!
      end.to change { advancing_step.reload.status }.to("completed")
        .and(change { advancing_step.completed_at }.from(nil))
        .and(not_change { in_progress_step.reload.status })
    end

    it "only updates steps for the configured pipelines" do
      other_pipeline = create(:pipeline, klass: "OtherPipeline")
      skipped_step = create(:step, status: :advancing, pipeline: other_pipeline)

      expect do
        pipeline.advance!
      end.not_to(change { skipped_step.reload.status })
    end

    it "does not mark the pipeline as complete if some steps not completed" do
      create(:step, status: :in_progress, pipeline: pipeline)

      expect do
        pipeline.advance!
      end.not_to(change { pipeline.reload.status })
    end

    it "marks the pipeline as complete if all steps are completed" do
      create(:step, status: :advancing, pipeline: pipeline)

      expect do
        pipeline.advance!
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
          pipeline.advance!
        end.to change(Ductwork::Step, :count).by(1)
          .and change(Ductwork::Job, :count).by(1)
        step = Ductwork::Step.last
        expect(step).to be_in_progress
        expect(step.klass).to eq("MyStepB")
        expect(step.step_type).to eq("default")
      end

      it "passes the output payload as input arguments to the next step" do
        allow(Ductwork::Job).to receive(:enqueue)

        pipeline.advance!

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
