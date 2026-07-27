# frozen_string_literal: true

# NOTE: pins down the outcome of an advancer being paused between selecting a
# candidate branch and claiming it, while a second advancer claims that same
# branch, advances it, and releases it. Candidate selection and claiming are two
# statements with no `SELECT ... FOR UPDATE` between them (branch claiming joins
# to `Step` and has to behave uniformly on SQLite, so it uses a CAS instead), so
# the paused advancer wakes up holding a candidate id whose branch has moved on:
# it is `in_progress` again with `claimed_for_advancing_at` back to NULL, but its
# latest step is a freshly enqueued `in_progress` one whose job has not run.
#
# Claiming it would advance the branch off a step that has produced no return
# value, routing on nil and minting a duplicate downstream step (at ~1M live
# branches the candidate scan takes long enough that this stopped being
# theoretical). The claiming UPDATE therefore re-asserts the entire candidate
# predicate -- branch status and "has a step in advancing/failed", not just the
# NULL claim -- so the stale claim matches zero rows and is treated like any
# other lost claim race.
RSpec.describe "Branch stops being claimable between selection and claim", :no_transaction do
  let(:pipeline) { create(:pipeline, :in_progress) }
  let(:pipeline_klass) { pipeline.klass }
  let(:run) { create(:run, :in_progress, pipeline:, pipeline_klass:, definition:) }
  let(:definition) do
    {
      nodes: %w[MyStepA.0 MyStepB.1],
      edges: {
        "MyStepA.0" => { to: %w[MyStepB.1], type: "chain", klass: "MyStepA" },
        "MyStepB.1" => { klass: "MyStepB" },
      },
    }.to_json
  end
  let(:branch) { create(:branch, :in_progress, pipeline_klass:, run:) }
  let(:step) do
    create(:step, :advancing, node: "MyStepA.0", klass: "MyStepA", branch: branch, run: run)
  end

  before do
    create(:job, step: step, output_payload: { payload: %w[a b c] }.to_json)
  end

  it "does not let the stale advancer claim the branch a second time" do
    pid = fork do
      Ductwork::Record.connection.reconnect!
      Ductwork::FaultInjection.with(:after_branch_candidate_select, :sleep) do
        # NOTE: this looks a little wonky but it basically simulates
        # creating the process record on "boot"
        create(:process, :current)
        Ductwork::BranchClaim.new(pipeline_klass).latest
      end
    end

    sleep(0.3) # give the child time to select the candidate and start sleeping

    create(:process, :current)
    advanced = Ductwork::Branch.with_latest_claimed(pipeline_klass) do |b, t, a|
      b.advance!(t, a)
    end
    Process.wait(pid)

    expect($?.exitstatus).to eq(0)
    expect(advanced).to be(:claimed)

    # the chain advanced exactly once: one transition over the original step,
    # one advancement under it, and one new step still waiting on its job
    expect(Ductwork::Transition.count).to eq(1)
    expect(Ductwork::Advancement.count).to eq(1)
    expect(Ductwork::Transition.sole.in_step_id).to eq(step.id)
    expect(step.reload).to be_completed

    next_step = branch.steps.where.not(id: step.id).sole
    expect(next_step).to be_in_progress
    expect(next_step.node).to eq("MyStepB.1")

    # and the branch is back where the successful advancer left it
    expect(branch.reload).to be_in_progress
    expect(branch.claimed_for_advancing_at).to be_nil
    expect(branch.claim_token).to be_nil
  end
end
