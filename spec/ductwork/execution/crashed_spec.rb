# frozen_string_literal: true

RSpec.describe Ductwork::Execution, "#crashed!" do
  subject(:execution) { create(:execution, job:) }

  let(:job) { create(:job) }
  let(:error) { Ductwork::ProcessCrash.new("Reaped from orphaned process") }

  it "completes the execution" do
    expect do
      execution.crashed!(error)
    end.to change { execution.reload.completed_at }.to(be_almost_now)
  end

  it "completes the attempt if it exists" do
    attempt = create(:attempt, execution:)

    expect do
      execution.crashed!(error)
    end.to change { attempt.reload.completed_at }.to(be_almost_now)
  end

  it "creates a 'process crashed' result record" do
    expect do
      execution.crashed!(error)
    end.to change(Ductwork::Result, :count).by(1)
    expect(execution.result.result_type).to eq("process_crashed")
  end

  it "records the crash marker on the result" do
    execution.crashed!(error)

    expect(execution.result).to have_attributes(
      error_klass: "Ductwork::ProcessCrash",
      error_message: "Reaped from orphaned process",
      error_backtrace: nil
    )
  end

  context "when the work loop passes the exception that killed it" do
    let(:error) do
      raise "boom"
    rescue RuntimeError => e
      e
    end

    it "records the class, message, and backtrace" do
      execution.crashed!(error)

      expect(execution.result).to have_attributes(
        error_klass: "RuntimeError",
        error_message: "boom"
      )
      expect(execution.result.error_backtrace).to include("crashed_spec.rb")
    end
  end

  # NOTE: text caps at 64KB on MySQL, so an unbounded backtrace can raise on
  # insert inside `crashed!` -- which is itself the recovery path
  context "when the backtrace is deeper than the frame limit" do
    let(:error) do
      raise "boom"
    rescue RuntimeError => e
      e.set_backtrace(Array.new(40) { |i| "frame_#{i}.rb:1:in 'call'" })
      e
    end

    it "keeps the frames nearest the raise and notes the rest" do
      execution.crashed!(error)

      lines = execution.result.error_backtrace.split("\n")
      expect(lines.length).to eq(11)
      expect(lines.first).to eq("frame_0.rb:1:in 'call'")
      expect(lines[9]).to eq("frame_9.rb:1:in 'call'")
      expect(lines.last).to eq("... 30 more frames")
    end
  end

  context "when the error message exceeds the column limit" do
    let(:error) { Ductwork::ThreadCrash.new("a" * 500) }

    it "truncates rather than failing the crash path" do
      execution.crashed!(error)

      expect(execution.result.error_message.length).to eq(255)
    end
  end

  it "creates new execution and availability records" do
    execution

    expect do
      execution.crashed!(error)
    end.to change(described_class, :count).by(1)
      .and change(Ductwork::Availability, :count).by(1)
  end

  context "when within the immediate-retry window" do
    subject(:execution) { create(:execution, job: job, crash_count: 0, retry_count: 2) }

    it "re-enqueues immediately with an incremented crash_count" do
      execution

      expect do
        execution.crashed!(error)
      end.to change(described_class, :count).by(1)
        .and change(Ductwork::Availability, :count).by(1)

      new_execution = job.executions.order(:created_at).last
      expect(new_execution.crash_count).to eq(1)
      expect(new_execution.retry_count).to eq(2)
      expect(new_execution.started_at).to be_almost_now
      expect(new_execution.availability.started_at).to be_almost_now
    end
  end

  context "when past the immediate-retry window but under the cap" do
    subject(:execution) { create(:execution, job: job, crash_count: 3) }

    before do
      Ductwork.configuration.job_worker_max_crash = 6
    end

    it "re-enqueues with a linear backoff" do
      execution.crashed!(error)

      new_execution = job.executions.order(:created_at).last
      expect(new_execution.crash_count).to eq(4)
      expect(new_execution.started_at).to be_within(2.seconds).of(40.seconds.from_now)
      expect(new_execution.availability.started_at).to be_within(2.seconds).of(40.seconds.from_now)
    end
  end

  context "when the crash cap is exceeded" do
    subject(:execution) { create(:execution, job: job, crash_count: 1) }

    before do
      execution.job.step.update!(status: "in_progress")
      Ductwork.configuration.job_worker_max_crash = 1
    end

    it "fails the step instead of re-enqueuing" do
      step = execution.job.step

      expect do
        execution.crashed!(error)
      end.to change { step.reload.status }.to("failed")
        .and not_change(described_class, :count)
        .and not_change(Ductwork::Availability, :count)
    end

    it "logs" do
      allow(Ductwork.logger).to receive(:error).and_call_original

      execution.crashed!(error)

      expect(Ductwork.logger).to have_received(:error).with(
        msg: "Job exceeded crash limit and failed",
        error_klass: "Ductwork::ProcessCrash",
        error_message: "Reaped from orphaned process",
        job_id: execution.job.id,
        job_klass: execution.job.klass,
        run_id: execution.job.step.run_id,
        role: :job_worker
      )
    end
  end

  it "no-ops if the execution is already completed" do
    execution.update!(completed_at: Time.current)

    expect do
      execution.crashed!(error)
    end.to not_change(described_class, :count)
      .and not_change(Ductwork::Availability, :count)
      .and not_change(Ductwork::Result, :count)
  end

  # NOTE: protects against the reaper racing the worker's rescue path where
  # both can converge on the same execution and otherwise produce duplicate
  # process_crashed results, replacement executions, and availabilities
  it "is idempotent when called twice on the same execution" do
    execution.crashed!(error)

    expect do
      execution.crashed!(error)
    end.to not_change(described_class, :count)
      .and not_change(Ductwork::Availability, :count)
      .and not_change(Ductwork::Result, :count)
  end

  # NOTE: the reaper loads an execution owned by one process and later calls
  # crashed! on that now-stale in-memory copy. If another process atomically
  # re-claims the same row in the meantime (new process_id, completed_at still
  # nil), the process_id fence must stop crashed! from clobbering that fresh
  # claim and spawning a duplicate replacement execution/availability/result.
  it "no-ops when the execution was reclaimed by another process" do
    owning_process = create(:process)
    execution.update!(process: owning_process)

    reclaiming_process = create(:process)
    described_class
      .where(id: execution.id)
      .update_all(process_id: reclaiming_process.id)

    expect do
      execution.crashed!(error)
    end.to not_change(described_class, :count)
      .and not_change(Ductwork::Availability, :count)
      .and not_change(Ductwork::Result, :count)

    expect(execution.reload.completed_at).to be_nil
    expect(execution.process_id).to eq(reclaiming_process.id)
  end
end
