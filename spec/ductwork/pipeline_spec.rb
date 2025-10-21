# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline do
  describe "validations" do
    let(:klass) { "MyPipeline" }
    let(:triggered_at) { Time.current }
    let(:status) { "in_progress" }
    let(:definition) { JSON.dump({}) }
    let(:definition_sha1) { Digest::SHA1.hexdigest(definition) }

    it "is invalid if the `klass` is not present" do
      pipeline = described_class.new(triggered_at:, status:, definition:, definition_sha1:)

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Klass can't be blank"])
    end

    it "is invalid if `triggered_at` is not present" do
      pipeline = described_class.new(klass:, status:, definition:, definition_sha1:)

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Triggered at can't be blank"])
    end

    it "is invalid if `status` is not present" do
      pipeline = described_class.new(klass:, triggered_at:, definition:, definition_sha1:)

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Status can't be blank"])
    end

    it "is invalid if `definition` is not present" do
      pipeline = described_class.new(klass:, triggered_at:, status:, definition_sha1:)

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Definition can't be blank"])
    end

    it "is invalid if `definition_sha1` is not present" do
      pipeline = described_class.new(klass:, triggered_at:, status:, definition:)

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Definition sha1 can't be blank"])
    end

    it "is valid otherwise" do
      pipeline = described_class.new(klass:, triggered_at:, status:, definition:, definition_sha1:)

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
        triggered_at: Time.current
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
      builder = instance_double(Ductwork::DefinitionBuilder, complete: nil)
      allow(Ductwork::DefinitionBuilder).to receive(:new).and_return(builder)

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
      end.to change(Ductwork.pipelines, :count).by(1)
      expect(Ductwork.pipelines).to eq(["MyPipeline"])
    end
  end

  describe ".trigger" do
    subject(:klass) do
      Class.new(described_class) do
        define do |pipeline|
          pipeline.start(MyFirstJob).chain(MySecondJob)
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
      expect(step.klass).to eq("MyFirstJob")
      expect(step.started_at).to be_present
    end

    it "enqueues a job" do
      expect do
        klass.trigger(args)
      end.to change(Ductwork::Job, :count).by(1)
        .and change(Ductwork::Execution, :count).by(1)
        .and change(Ductwork::Availability, :count).by(1)
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
end
