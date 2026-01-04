# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline do
  describe "validations" do
    let(:klass) { "MyPipeline" }
    let(:triggered_at) { Time.current }
    let(:started_at) { 10.minutes.from_now }
    let(:last_advanced_at) { Time.current }
    let(:status) { "in_progress" }
    let(:definition) { JSON.dump({}) }
    let(:definition_sha1) { Digest::SHA1.hexdigest(definition) }

    it "is invalid if the `klass` is not present" do
      pipeline = described_class.new(
        triggered_at:,
        started_at:,
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
        started_at:,
        last_advanced_at:,
        status:,
        definition:,
        definition_sha1:
      )

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Triggered at can't be blank"])
    end

    it "is invalid if `started_at` is not present" do
      pipeline = described_class.new(
        klass:,
        triggered_at:,
        last_advanced_at:,
        status:,
        definition:,
        definition_sha1:
      )

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Started at can't be blank"])
    end

    it "is invalid if `last_advanced_at` is not present" do
      pipeline = described_class.new(
        klass:,
        triggered_at:,
        started_at:,
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
        started_at:,
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
        started_at:,
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
        started_at:,
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
        started_at:,
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
        started_at: Time.current,
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

    before do
      Ductwork.defined_pipelines = nil
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
          pipeline.start(MyFirstStep)
        end

        klass.define do |pipeline|
          pipeline.start(MyFirstStep)
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
          pipeline.start(MyFirstStep)
        end
      end.to change(klass, :pipeline_definition).from(nil)
    end

    it "adds the pipeline to whole set of pipelines" do
      expect do
        klass.define do |pipeline|
          pipeline.start(MyFirstStep)
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
      allow(SecureRandom).to receive(:hex).and_return("a1b2c3d4")
      pipeline = nil

      expect do
        pipeline = klass.trigger(args)
      end.to change(Ductwork::Step, :count).by(1)
      step = pipeline.steps.reload.first
      expect(step).to be_start
      expect(step.node).to eq("MyFirstStep.a1b2c3d4")
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

    it "correctly passes an array argument to the job" do
      allow(Ductwork::Job).to receive(:enqueue)

      klass.trigger([1, 2])

      expect(Ductwork::Job).to have_received(:enqueue).with(anything, [1, 2])
    end

    it "correctly passes multiple positional arguments to the job" do
      allow(Ductwork::Job).to receive(:enqueue)

      klass.trigger(1, 2)

      expect(Ductwork::Job).to have_received(:enqueue).with(anything, 1, 2)
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

  describe "#parsed_definition" do
    it "returns a JSON parsed indifferent hash" do
      pipeline = described_class.new(definition: JSON.dump({ foo: "bar" }))

      expect(pipeline.parsed_definition[:foo]).to eq("bar")
      expect(pipeline.parsed_definition["foo"]).to eq("bar")
    end
  end

  describe "#complete!" do
    let(:pipeline) { create(:pipeline, status: "in_progress") }

    it "sets the status and completed at timestamp" do
      expect do
        pipeline.complete!
      end.to change(pipeline, :status).to("completed")
        .and change(pipeline, :completed_at).to be_within(1.second).of(Time.current)
    end

    it "logs" do
      allow(Ductwork.logger).to receive(:info).and_call_original

      pipeline.complete!

      expect(Ductwork.logger).to have_received(:info).with(
        msg: "Pipeline completed",
        pipeline_id: pipeline.id,
        role: :pipeline_advancer
      )
    end
  end

  describe "#halt!" do
    let(:pipeline) { create(:pipeline, status: "in_progress") }

    it "sets the status" do
      expect do
        pipeline.halt!
      end.to change(pipeline, :status).to("halted")
    end

    it "updates the halted at timestamp" do
      expect do
        pipeline.halt!
      end.to change(pipeline, :halted_at).from(nil).to be_within(1.second).of(Time.current)
    end

    it "logs" do
      allow(Ductwork.logger).to receive(:info).and_call_original

      pipeline.halt!

      expect(Ductwork.logger).to have_received(:info).with(
        msg: "Pipeline halted",
        pipeline_id: pipeline.id,
        pipeline_klass: pipeline.klass
      )
    end
  end
end
