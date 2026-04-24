# frozen_string_literal: true

RSpec.describe Ductwork::Job do
  describe "validations" do
    let(:klass) { "MyFirstStep" }
    let(:started_at) { Time.current }
    let(:input_args) { 1 }

    it "is invalid when klass is blank" do
      job = described_class.new(started_at:, input_args:)

      expect(job).not_to be_valid
      expect(job.errors.full_messages).to eq(["Klass can't be blank"])
    end

    it "is invalid when started_at is blank" do
      job = described_class.new(klass:, input_args:)

      expect(job).not_to be_valid
      expect(job.errors.full_messages).to eq(["Started at can't be blank"])
    end

    it "is invalid when input_args is blank" do
      job = described_class.new(klass:, started_at:)

      expect(job).not_to be_valid
      expect(job.errors.full_messages).to eq(["Input args can't be blank"])
    end

    it "is valid otherwise" do
      job = described_class.new(klass:, started_at:, input_args:)

      expect(job).to be_valid
    end
  end

  describe ".claim_latest" do
    let(:availability) { create(:availability) }
    let(:execution) { availability.execution }
    let(:klass) { execution.job.step.run.pipeline_klass }
    let(:process) { create(:process, :current) }

    before do
      process
      availability.update!(pipeline_klass: klass)
    end

    it "calls the job claim class" do
      claim = instance_double(Ductwork::JobClaim, latest: nil)
      allow(Ductwork::JobClaim).to receive(:new).and_return(claim)

      described_class.claim_latest(klass)

      expect(Ductwork::JobClaim).to have_received(:new).with(klass)
      expect(claim).to have_received(:latest)
    end

    it "updates the the availability record" do
      expect do
        described_class.claim_latest(klass)
      end.to change { availability.reload.completed_at }.from(nil).to(be_almost_now)
        .and change(availability, :process_id).from(nil).to(process.id)
    end

    it "only claims jobs for the specified pipeline klass" do
      other_availability = create(:availability)
      pipeline = other_availability.execution.job.step.run.pipeline

      expect do
        described_class.claim_latest(pipeline.class.name)
      end.not_to change { other_availability.reload.process_id }.from(nil)
    end

    it "does not claim job execution availabilities in the future" do
      future_availability = create(:availability, started_at: 5.seconds.from_now)

      expect do
        described_class.claim_latest(klass)
      end.not_to change { future_availability.reload.completed_at }.from(nil)
    end

    it "changes waiting pipeline and step statuses to in-progress" do
      step = execution.job.step
      run = step.run
      pipeline = run.pipeline

      step.update!(status: "waiting")
      run.update!(status: "waiting")
      pipeline.update!(status: "waiting")

      expect do
        described_class.claim_latest(klass)
      end.to change { pipeline.reload.status }.from("waiting").to("in_progress")
        .and change { run.reload.status }.from("waiting").to("in_progress")
        .and change { step.reload.status }.from("waiting").to("in_progress")
    end
  end

  describe ".enqueue" do
    let(:step) { create(:step) }
    let(:args) { %i[foo bar] }

    it "creates a job record" do
      expect do
        described_class.enqueue(step, args)
      end.to change(described_class, :count).by(1)
        .and change(step, :job).from(nil)

      job = described_class.sole
      expect(job.klass).to eq("MyFirstStep")
      expect(job.started_at).to be_almost_now
      expect(job.completed_at).to be_nil
      expect(job.input_args).to eq(JSON.dump({ args: [args] }))
      expect(job.output_payload).to be_nil
      expect(job.step).to eq(step)
    end

    it "creates an execution record" do
      expect do
        described_class.enqueue(step, args)
      end.to change(Ductwork::Execution, :count).by(1)

      job = described_class.sole
      execution = job.executions.sole
      expect(execution.started_at).to be_almost_now
      expect(execution.completed_at).to be_nil
    end

    it "creates an availability record" do
      expect do
        described_class.enqueue(step, args)
      end.to change(Ductwork::Availability, :count).by(1)

      execution = Ductwork::Execution.sole
      availability = execution.availability
      expect(availability.started_at).to be_almost_now
      expect(availability.completed_at).to be_nil
    end
  end

  describe "#execution_crashed!" do
    subject(:job) { create(:job) }

    let(:execution) { create(:execution, job:) }

    it "completes the execution" do
      expect do
        job.execution_crashed!(execution)
      end.to change { execution.reload.completed_at }.to(be_almost_now)
    end

    it "completes the attempt if it exists" do
      attempt = create(:attempt, execution:)

      expect do
        job.execution_crashed!(execution)
      end.to change { attempt.reload.completed_at }.to(be_almost_now)
    end

    it "creates a 'process crashed' result record" do
      expect do
        job.execution_crashed!(execution)
      end.to change(Ductwork::Result, :count).by(1)
      expect(execution.result.result_type).to eq("process_crashed")
    end

    it "creates new execution and availability records" do
      execution

      expect do
        job.execution_crashed!(execution)
      end.to change(Ductwork::Execution, :count).by(1)
        .and change(Ductwork::Availability, :count).by(1)
    end
  end

  describe "#return_value" do
    subject(:job) { described_class.new(output_payload:) }

    let(:output_payload) { { payload: }.to_json }

    context "when the output payload holds a nil value" do
      let(:payload) { nil }

      it "returns nil" do
        expect(job.return_value).to be_nil
      end
    end

    context "when the output payload holds values" do
      let(:payload) { %w[a b c] }

      it "returns the value" do
        expect(job.return_value).to eq(%w[a b c])
      end
    end

    context "when the output payload is nil" do
      let(:output_payload) { nil }

      it "returns nil" do
        expect(job.return_value).to be_nil
      end
    end
  end
end
