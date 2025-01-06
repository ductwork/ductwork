# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline do
  describe ".define" do
    subject(:klass) do
      Class.new do
        include Ductwork::Pipeline

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
      job_class1 = Class.new do
        def self.name
          "MyFirstJob"
        end
      end
      job_class2 = Class.new do
        def self.name
          "MySecondJob"
        end
      end

      Class.new do
        include Ductwork::Pipeline

        define do |pipeline|
          pipeline.start(job_class1).chain(job_class2)
        end

        def self.name
          "MyPipeline"
        end
      end
    end

    let(:args) { 1 }

    it "creates and returns a pipeline instance record" do
      instance = nil

      expect do
        instance = klass.trigger(args)
      end.to change(Ductwork::PipelineInstance, :count).by(1)
      expect(instance.name).to eq("MyPipeline")
      expect(instance).to be_in_progress
      expect(instance.triggered_at).to be_present
      expect(instance.completed_at).to be_nil
      expect(instance.steps.count).to eq(2)
    end

    it "creates step records" do
      expect do
        klass.trigger(args)
      end.to change(Ductwork::Step, :count).by(2)
      step1, step2 = Ductwork::Step.all
      expect(step1).to be_start
      expect(step1.klass).to eq("MyFirstJob")
      expect(step1.started_at).to be_present
      expect(step2).to be_default
      expect(step2.klass).to eq("MySecondJob")
      expect(step2.started_at).to be_nil
    end

    it "assigns step order" do
      klass.trigger(args)

      step1, step2 = Ductwork::Step.all
      expect(step1.previous_step).to be_nil
      expect(step1.next_step).to eq(step2)
      expect(step2.previous_step).to eq(step1)
      expect(step2.next_step).to be_nil
    end

    xit "enqueues the job"

    it "creates a job record" do
      pending "need to make decisions on job wrapping first"

      expect do
        klass.trigger(args)
      end.to change(Ductwork::Job, :count).by(1)
      job = Ductwork::Job.last
      expect(job.native_id).to be_present
      expect(job.enqueued_at).to be_present
    end
  end
end
