# frozen_string_literal: true

RSpec.describe Ductwork::Execution, "#call" do
  subject(:execution) { create(:execution, job:) }

  let(:job) { Ductwork::Job.create!(klass:, started_at:, input_args:, step:) }
  let(:klass) { "MyFirstStep" }
  let(:started_at) { Time.current }
  let(:input_args) { JSON.dump({ args: 1 }) }
  let(:step) { create(:step, status: :in_progress) }
  let(:pipeline_klass) { step.run.pipeline_klass }

  it "deserializes the step constant, initializes, and executes it" do
    user_step = instance_double(MyFirstStep, execute: nil)
    allow(MyFirstStep).to receive(:build_for_execution).and_return(user_step)

    execution.call(pipeline_klass)

    expect(MyFirstStep).to have_received(:build_for_execution).with(step.run.id, 1)
    expect(user_step).to have_received(:execute)
  end

  it "updates the job record with the output payload" do
    payload = JSON.dump(payload: "return_value")

    expect do
      execution.call(pipeline_klass)
    end.to change(job, :output_payload).from(nil).to(payload)
      .and change(job, :completed_at).from(nil).to(be_almost_now)
  end

  it "creates an attempt record" do
    expect do
      execution.call(pipeline_klass)
    end.to change(Ductwork::Attempt, :count).by(1)
    attempt = Ductwork::Attempt.sole
    expect(attempt.started_at).to be_almost_now
    expect(attempt.completed_at).to be_almost_now
  end

  it "updates the timestamp on the execution" do
    expect do
      execution.call(pipeline_klass)
    end.to change { execution.reload.completed_at }.from(nil).to(be_almost_now)
  end

  it "creates a success result record when execution succeeds" do
    expect do
      execution.call(pipeline_klass)
    end.to change(Ductwork::Result, :count).by(1)
    result = Ductwork::Result.sole
    expect(result.result_type).to eq("success")
  end

  it "marks the step as 'advancing' when the job execution completes" do
    expect do
      execution.call(pipeline_klass)
    end.to change { step.reload.status }.from("in_progress").to("advancing")
  end

  it "does not mark the step as 'advancing' if the job execution raises" do
    user_step = instance_double(MyFirstStep)
    allow(user_step).to receive(:execute).and_raise(StandardError, "bad times")
    allow(MyFirstStep).to receive(:build_for_execution).and_return(user_step)

    expect do
      execution.call(pipeline_klass)
    end.not_to change { step.reload.status }.from("in_progress")
  end

  context "when execution errors" do
    before do
      user_step = instance_double(MyFirstStep)
      allow(user_step).to receive(:execute).and_raise(StandardError, "bad times")
      allow(MyFirstStep).to receive(:build_for_execution).and_return(user_step)
    end

    it "creates a failure result record" do
      expect do
        expect do
          execution.call(pipeline_klass)
        end.not_to raise_error
      end.to change(Ductwork::Result, :count).by(1)
      result = Ductwork::Result.sole
      expect(result.result_type).to eq("failure")
      expect(result.error_klass).to eq("StandardError")
      expect(result.error_message).to eq("bad times")
      expect(result.error_backtrace).to be_present
    end

    it "creates a new future available execution" do
      execution

      expect do
        execution.call(pipeline_klass)
      end.to change(described_class, :count).by(1)
        .and change(Ductwork::Availability, :count).by(1)
      next_execution = job.executions.last
      expect(next_execution.retry_count).to eq(1)
      expect(next_execution.started_at).to be_within(1.second).of(10.seconds.from_now)
      expect(next_execution.availability.started_at).to be_within(1.second).of(10.seconds.from_now)
    end

    it "logs" do
      allow(Ductwork.logger).to receive(:warn).and_call_original

      execution.call(pipeline_klass)

      expect(Ductwork.logger).to have_received(:warn).with(
        msg: "Job errored",
        error_klass: "StandardError",
        error_message: "bad times",
        job_id: job.id,
        job_klass: job.klass,
        run_id: step.run.id,
        role: :job_worker
      )
    end

    context "when retries are exhausted" do
      subject!(:execution) { create(:execution, retry_count: 2, job: job) }

      before do
        step.branch.in_progress!
        Ductwork.configuration.job_worker_max_retry = 2
      end

      it "marks the step as failed" do
        expect do
          execution.call(pipeline_klass)
        end.to change { step.reload.status }.from("in_progress").to("failed")
      end

      it "logs" do
        allow(Ductwork.logger).to receive(:error).and_call_original

        execution.call(pipeline_klass)

        expect(Ductwork.logger).to have_received(:error).with(
          msg: "Job exhausted retries and failed",
          error_klass: "StandardError",
          error_message: "bad times",
          job_id: job.id,
          job_klass: job.klass,
          run_id: step.run.id,
          role: :job_worker
        )
      end
    end
  end
end
