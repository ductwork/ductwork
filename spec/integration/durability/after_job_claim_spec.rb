# frozen_string_literal: true

RSpec.describe "Crash after job claim before execution", :no_transaction do
  let(:pipeline) { create(:pipeline, :in_progress) }
  let(:pipeline_klass) { pipeline.klass }
  let(:id) { Kernel.rand(1..100) }
  let(:klass) { "MyStepA" }
  let(:run) { create(:run, :in_progress, pipeline_klass:, pipeline:) }
  let(:branch) { create(:branch, :in_progress, pipeline_klass:, run:) }
  let(:step) { create(:step, :in_progress) }
  let(:job) { create(:job, klass:, step:) }
  let(:execution) { create(:execution, job:) }
  let(:availability) { create(:availability, pipeline_klass:, execution:) }

  before do
    availability
  end

  it "recovers the job and the execution completes via the reaper" do
    pid = fork do
      Ductwork::Record.connection.reconnect!
      Ductwork::FaultInjection.with(:after_job_claim, :kill) do
        # NOTE: this looks a little wonky but it basically simulates
        # creating the process record on "boot"
        create(:process, :current)
        Ductwork::Processes::JobWorker
          .new(pipeline_klass, id)
          .tap(&:start)
          .join(1)
      end
    end

    Process.wait(pid)
    expect($?.termsig).to eq(Signal.list["KILL"])
    expect(execution.reload.completed_at).to be_nil
    expect(availability.reload.completed_at).to be_almost_now

    post_reap_threshold = Ductwork::Process::REAP_THRESHOLD.from_now + 1.second
    # NOTE: again, simulating the parent process creating the process record
    # on "boot" post-reaping
    create(:process, :current, last_heartbeat_at: post_reap_threshold)
    worker = Ductwork::Processes::JobWorker.new(pipeline_klass, id)

    travel_to(post_reap_threshold) do
      Ductwork::Process.reap_all!(:process_supervisor)
      worker.start
      sleep(1)
    end

    new_execution = job.executions.last
    expect(job.executions.count).to eq(2)
    expect(execution.reload.completed_at).to be_within(5.seconds).of(post_reap_threshold)
    expect(new_execution.completed_at).to be_within(5.seconds).of(post_reap_threshold)

    worker.stop
    worker.join(2)

    expect(worker).not_to be_alive
  end
end
