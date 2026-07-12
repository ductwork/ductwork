# frozen_string_literal: true

# NOTE: pins down the outcome of a process being reaped (heartbeat-stale,
# destroyed) while it is concurrently paused between `Process.current`
# returning a soon-to-be-destroyed record and `transition.advancements.create!`
# referencing it -- the exact race the "no global-timeout sweep for claims
# unreachable through process records" durability finding worried about.
#
# Empirically, across sqlite and postgres, the race never produces a silent
# orphan (an advancement stuck at process_id: nil, completed_at: nil forever).
# Depending on which side reaches the database lock first:
#   - the reaper runs second and its sweep correctly sees and crash-marks the
#     just-committed advancement, or
#   - the reaper runs first, destroys the process, and the zombie's `create!`
#     then fails outright with ActiveRecord::InvalidForeignKey (confirmed via
#     Postgres's real FK-check row lock), cleanly rolling back the whole claim
#     transaction (branch + transition + advancement) via `transaction do`'s
#     default rollback-on-exception.
# The second case is real but unhandled: `PipelineAdvancer#work_loop` has no
# rescue around `Branch.with_latest_claimed`, so that exception kills the
# advancer's Thread outright (recovered later by `WorkerHealthCheck`, but with
# no structured log entry attributing the crash to this race).
RSpec.describe "Reaper destroys a Process record while it is mid-claim", :no_transaction do
  let(:pipeline) { create(:pipeline, :in_progress) }
  let(:pipeline_klass) { pipeline.klass }
  let(:run) { create(:run, :in_progress, pipeline:) }
  let(:branch) { create(:branch, :in_progress, pipeline_klass:, run:) }
  let(:step) { create(:step, :failed, branch:, run:) }

  before do
    step
  end

  it "never leaves an advancement permanently unreachable (process_id: nil, completed_at: nil)" do
    pid = fork do
      Ductwork::Record.connection.reconnect!
      Ductwork::FaultInjection.with(:before_advancement_create, :sleep) do
        create(:process, :current)
        Ductwork::BranchClaim.new(pipeline_klass).latest
      rescue StandardError
        # NOTE: losing the race raises here (see module doc above); swallowed
        # so the forked process exits and the parent isn't left waiting.
      end
    end

    sleep(0.3) # give the child time to reach the checkpoint and start sleeping
    Ductwork::Process.find_by(pid:)&.reap!(:process_supervisor, force: true)
    Process.wait(pid)

    orphaned = Ductwork::Advancement.where(process_id: nil, completed_at: nil)
    expect(orphaned).to be_empty
  end
end
