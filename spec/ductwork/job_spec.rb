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

    it "updates the the availability record" do
      be_almost_now = be_within(1.second).of(Time.current)

      expect do
        described_class.claim_latest
      end.to change { availability.reload.completed_at }.from(nil).to(be_almost_now)
        .and change(availability, :process_id).from(nil).to(::Process.pid)
    end

    it "updates the execution record" do
      expect do
        described_class.claim_latest
      end.to change { execution.reload.process_id }.from(nil).to(::Process.pid)
    end

    it "does not claim job execution availabilities in the future" do
      future_availability = create(:availability, started_at: 5.seconds.from_now)

      expect do
        described_class.claim_latest
      end.not_to change { future_availability.reload.completed_at }.from(nil)
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
      expect(job.started_at).to be_within(1.second).of(Time.current)
      expect(job.completed_at).to be_nil
      expect(job.input_args).to eq(JSON.dump({ args: }))
      expect(job.output_payload).to be_nil
      expect(job.step).to eq(step)
    end

    it "creates an execution record" do
      expect do
        described_class.enqueue(step, args)
      end.to change(Ductwork::Execution, :count).by(1)

      job = described_class.sole
      execution = job.executions.sole
      expect(execution.started_at).to be_within(1.second).of(Time.current)
      expect(execution.completed_at).to be_nil
    end

    it "creates an availability record" do
      expect do
        described_class.enqueue(step, args)
      end.to change(Ductwork::Availability, :count).by(1)

      execution = Ductwork::Execution.sole
      availability = execution.availability
      expect(availability.started_at).to be_within(1.second).of(Time.current)
      expect(availability.completed_at).to be_nil
    end
  end

  describe "#execute!" do
    subject(:job) do
      described_class.create!(klass:, started_at:, input_args:, step:)
    end

    let(:klass) { "MyFirstStep" }
    let(:started_at) { Time.current }
    let(:input_args) { JSON.dump({ args: 1 }) }
    let(:step) { create(:step, status: :in_progress) }
    let!(:execution) { create(:execution, job:) }

    it "deserializes the step constant, initializes, and executes it" do
      user_step = instance_double(MyFirstStep, execute: nil)
      allow(MyFirstStep).to receive(:new).and_return(user_step)

      job.execute(step.pipeline)

      expect(MyFirstStep).to have_received(:new).with(1)
      expect(user_step).to have_received(:execute)
    end

    it "updates the job record with the output payload" do
      payload = JSON.dump(payload: "return_value")

      expect do
        job.execute(step.pipeline)
      end.to change(job, :output_payload).from(nil).to(payload)
        .and change(job, :completed_at).from(nil).to(be_within(1.second).of(Time.current))
    end

    it "creates a run record" do
      expect do
        job.execute(step.pipeline)
      end.to change(Ductwork::Run, :count).by(1)
      run = Ductwork::Run.sole
      expect(run.started_at).to be_within(1.second).of(Time.current)
      expect(run.completed_at).to be_within(1.second).of(Time.current)
    end

    it "updates the timestamp on the execution" do
      be_almost_now = be_within(1.second).of(Time.current)

      expect do
        job.execute(step.pipeline)
      end.to change { execution.reload.completed_at }.from(nil).to(be_almost_now)
    end

    it "creates a success result record when execution succeeds" do
      expect do
        job.execute(step.pipeline)
      end.to change(Ductwork::Result, :count).by(1)
      result = Ductwork::Result.sole
      expect(result.result_type).to eq("success")
    end

    it "creates a failure result record when execution fails" do
      user_step = instance_double(MyFirstStep)
      allow(user_step).to receive(:execute).and_raise(StandardError, "bad times")
      allow(MyFirstStep).to receive(:new).and_return(user_step)

      expect do
        expect do
          job.execute(step.pipeline)
        end.not_to raise_error
      end.to change(Ductwork::Result, :count).by(1)
      result = Ductwork::Result.sole
      expect(result.result_type).to eq("failure")
      expect(result.error_klass).to eq("StandardError")
      expect(result.error_message).to eq("bad times")
      expect(result.error_backtrace).to be_present
    end

    it "creates a new execution available in the future" do
      user_step = instance_double(MyFirstStep)
      allow(user_step).to receive(:execute).and_raise(StandardError, "bad times")
      allow(MyFirstStep).to receive(:new).and_return(user_step)

      job.execute(step.pipeline)

      execution = job.executions.last
      expect(execution.retry_count).to eq(1)
      expect(execution.availability.started_at).to be_within(1.second).of(10.seconds.from_now)
    end

    it "marks the step as 'advancing' when the job execution completes" do
      expect do
        job.execute(step.pipeline)
      end.to change { step.reload.status }.from("in_progress").to("advancing")
    end

    it "does not mark the step as 'advancing' if the job execution raises" do
      user_step = instance_double(MyFirstStep)
      allow(user_step).to receive(:execute).and_raise(StandardError, "bad times")
      allow(MyFirstStep).to receive(:new).and_return(user_step)

      expect do
        job.execute(step.pipeline)
      end.not_to change { step.reload.status }.from("in_progress")
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
