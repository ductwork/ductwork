# frozen_string_literal: true

RSpec.describe "Crash after branch claim before advancement", :no_transaction do
  let(:pipeline) { create(:pipeline, :in_progress) }
  let(:pipeline_klass) { pipeline.klass }
  let(:run) { create(:run, :in_progress, pipeline:) }
  let(:branch) { create(:branch, :in_progress, pipeline_klass:, run:) }
  let(:step) { create(:step, :failed, branch:, run:) }

  before do
    step
  end

  it "recovers the branch and the advancement completes via the reaper" do
    pid = fork do
      Ductwork::Record.connection.reconnect!
      Ductwork::FaultInjection.with(:after_branch_claim, :kill) do
        # NOTE: this looks a little wonky but it basically simulates
        # creating the process record on "boot"
        create(:process, :current)
        Ductwork::Processes::PipelineAdvancer
          .new(pipeline_klass)
          .tap(&:start)
          .join(2)
      end
    end

    Process.wait(pid)
    expect($?.termsig).to eq(Signal.list["KILL"])

    transition = branch.transitions.sole
    expect(transition.completed_at).to be_nil
    expect(transition.advancements.sole.process).to be_present
    expect(transition.advancements.sole.completed_at).to be_nil
    expect(branch.reload.claimed_for_advancing_at).to be_present

    post_reap_threshold = Ductwork::Process::REAP_THRESHOLD.from_now + 1.second
    advancer = Ductwork::Processes::PipelineAdvancer.new(pipeline_klass)

    travel_to(post_reap_threshold) do
      Ductwork::Process.reap_all!(:process_supervisor)
      advancer.start
      sleep(1)
    end

    expect(branch.reload.claimed_for_advancing_at).to be_nil
    expect(branch.reload.status).to eq("halted")
    expect(branch.halt_reason).to eq("job_retries_exhausted")
    expect(transition.reload.completed_at).to be_present
    expect(transition.advancements.last.completed_at).to be_present

    advancer.stop
    advancer.join(2)

    expect(advancer).not_to be_alive
  end
end
