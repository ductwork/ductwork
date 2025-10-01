# frozen_string_literal: true

RSpec.xdescribe Ductwork::Pipeline do
  describe "validations" do
    let(:klass) { "MyPipeline" }
    let(:triggered_at) { Time.current }
    let(:status) { "in_progress" }

    it "is invalid if the `klass` is not present" do
      pipeline = described_class.new(triggered_at:, status:)

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Name can't be blank"])
    end

    it "is invalid if `triggered_at` is not present" do
      pipeline = described_class.new(klass:, status:)

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Triggered at can't be blank"])
    end

    it "is invalid if `status` is not present" do
      pipeline = described_class.new(klass:, triggered_at:)

      expect(pipeline).not_to be_valid
      expect(pipeline.errors.full_messages).to eq(["Status can't be blank"])
    end

    it "is valid otherwise" do
      pipeline = described_class.new(klass:, triggered_at:, status:)

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
      expect(pipeline.triggered_at).to be_present
      expect(pipeline.completed_at).to be_nil
      expect(pipeline.steps.count).to eq(2)
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

    it "creates a job record" do
      Ductwork.configuration = instance_double(
        Ductwork::Configuration,
        adapter: "sidekiq",
        job_queue: "high-priority"
      )

      expect do
        klass.trigger(args)
      end.to change(Ductwork::Job, :count).by(1)
      job = Ductwork::Job.last
      expect(job).to be_running
      expect(job).to be_sidekiq
      expect(job.jid).to be_present
      expect(job.enqueued_at).to be_present
    end
  end
end
