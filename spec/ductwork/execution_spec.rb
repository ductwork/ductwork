# frozen_string_literal: true

RSpec.describe Ductwork::Execution do
  describe "validations" do
    let(:retry_count) { rand(0..2) }
    let(:started_at) { Time.current }

    it "is invalid when started_at is blank" do
      execution = described_class.new(retry_count:)

      expect(execution).not_to be_valid
      expect(execution.errors.full_messages.sole).to eq("Started at can't be blank")
    end

    it "is invalid when retry_count is blank" do
      execution = described_class.new(started_at:)

      expect(execution).not_to be_valid
      expect(execution.errors.full_messages.sole).to eq("Retry count can't be blank")
    end

    it "is valid otherwise" do
      execution = described_class.new(started_at:, retry_count:)

      expect(execution).to be_valid
    end
  end

  describe "#succeeded!" do
    subject(:execution) { create(:execution, process:) }

    let(:output_payload) { 1 }
    let(:serialized_payload) { JSON.dump({ payload: output_payload }) }
    let(:attempt) { create(:attempt, execution:) }
    let(:process) { create(:process, :current) }

    before do
      attempt
    end

    it "atomically completes the execution" do
      expect do
        execution.succeeded!(output_payload)
      end.to change { execution.reload.completed_at }.from(nil).to(be_almost_now)
    end

    it "sets the payload and completes the job" do
      expect do
        execution.succeeded!(output_payload)
      end.to change(execution.job, :output_payload).to(serialized_payload)
        .and change(execution.job, :completed_at).from(nil).to(be_almost_now)
    end

    it "completes the attempt" do
      expect do
        execution.succeeded!(output_payload)
      end.to change { attempt.reload.completed_at }.from(nil).to(be_almost_now)
    end

    it "sets the step to advancing" do
      execution.job.step.update!(status: "in_progress")

      expect do
        execution.succeeded!(output_payload)
      end.to change(execution.job.step, :status).to("advancing")
    end

    it "creates a result" do
      expect do
        execution.succeeded!(output_payload)
      end.to change(Ductwork::Result, :count).by(1)
      expect(execution.result).to be_success
    end

    it "is idempotent" do
      execution.succeeded!(output_payload)

      expect do
        execution.succeeded!("another_output_payload")
      end.to not_change { execution.job.output_payload }.from(serialized_payload)
    end
  end

  describe "#errored!" do
    subject(:execution) { create(:execution, process:, retry_count:) }

    let(:process) { create(:process, :current) }
    let(:retry_count) { 1 }
    let(:attempt) { create(:attempt, execution:) }
    let(:error) do
      StandardError.new("bad times").tap do |e|
        e.set_backtrace(caller)
      end
    end

    before do
      attempt
    end

    it "atomically completes the execution" do
      expect do
        execution.errored!(error)
      end.to change { execution.reload.completed_at }.from(nil).to(be_almost_now)
    end

    it "completes the attempt" do
      expect do
        execution.errored!(error)
      end.to change { attempt.reload.completed_at }.from(nil).to(be_almost_now)
    end

    it "creates a result" do
      expect do
        execution.errored!(error)
      end.to change(Ductwork::Result, :count).by(1)

      result = execution.result
      expect(result).to be_failure
      expect(result.error_klass).to eq("StandardError")
      expect(result.error_message).to eq("bad times")
      expect(result.error_backtrace).to be_present
    end

    it "is idempotent" do
      execution.errored!(error)

      expect do
        execution.errored!(error)
      end.to not_change(described_class, :count)
        .and not_change(Ductwork::Availability, :count)
    end

    context "when there are more retries left" do
      before do
        Ductwork.configuration.job_worker_max_retry = 4
      end

      it "creates a new execution and availability" do
        expect do
          execution.errored!(error)
        end.to change(described_class, :count).by(1)
          .and change(Ductwork::Availability, :count).by(1)

        new_execution = execution.job.executions.last
        expect(new_execution.retry_count).to eq(2)
        expect(new_execution.crash_count).to eq(0)
        expect(new_execution.started_at).to be_within(2.seconds).of(10.seconds.from_now)
      end

      it "logs" do
        allow(Ductwork.logger).to receive(:warn).and_call_original

        execution.errored!(error)

        expect(Ductwork.logger).to have_received(:warn).with(
          msg: "Job errored",
          error_klass: "StandardError",
          error_message: "bad times",
          job_id: execution.job_id,
          job_klass: execution.job.klass,
          run_id: execution.job.step.run_id,
          role: :job_worker
        )
      end
    end

    context "when retries are exhausted" do
      before do
        execution.job.step.update!(status: "in_progress")
        Ductwork.configuration.job_worker_max_retry = 1
      end

      it "fails the step" do
        expect do
          execution.errored!(error)
        end.to change(execution.job.step, :status).to("failed")
      end

      it "logs" do
        allow(Ductwork.logger).to receive(:error).and_call_original

        execution.errored!(error)

        expect(Ductwork.logger).to have_received(:error).with(
          msg: "Job exhausted retries and failed",
          error_klass: "StandardError",
          error_message: "bad times",
          job_id: execution.job_id,
          job_klass: execution.job.klass,
          run_id: execution.job.step.run_id,
          role: :job_worker
        )
      end
    end
  end
end
