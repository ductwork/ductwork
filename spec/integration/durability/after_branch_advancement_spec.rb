# frozen_string_literal: true

RSpec.describe "Crash after branch advancement", :no_transaction do
  let(:pipeline) { create(:pipeline, :in_progress) }
  let(:pipeline_klass) { pipeline.klass }
  let(:run) { create(:run, :in_progress, pipeline:) }
  let(:branch) { create(:branch, :in_progress, pipeline_klass:, run:) }
  let(:step) { create(:step, :advancing, branch:, run:) }

  before do
    step
  end

  it "re-claims the branch and completes it" do
    pid = fork do
      Ductwork::Record.connection.reconnect!
      Ductwork::FaultInjection.with(:after_branch_advancement, :kill) do
        # NOTE: this looks a little wonky but it basically simulates
        # creating the process record on "boot"
        create(:process, :current)
        Ductwork::Processes::PipelineAdvancer
          .new(pipeline_klass)
          .tap(&:start)
          .join(1)
      end
    end

    Process.wait(pid)
    expect($?.termsig).to eq(Signal.list["KILL"])

    transition = branch.transitions.sole
    expect(transition.completed_at).to be_almost_now
    expect(transition.advancements.sole.process).to be_present
    expect(transition.advancements.sole.completed_at).to be_almost_now
    expect(branch.reload.claimed_for_advancing_at).to be_nil

    post_reap_threshold = Ductwork::Process::REAP_THRESHOLD.from_now + 1.second
    advancer = Ductwork::Processes::PipelineAdvancer.new(pipeline_klass)

    travel_to(post_reap_threshold) do
      advancer.start
      sleep(1)
    end

    expect(branch.reload.status).to eq("completed")
    expect(transition.advancements.count).to eq(1)

    advancer.stop
    advancer.join(2)

    expect(advancer).not_to be_alive
  end
end
