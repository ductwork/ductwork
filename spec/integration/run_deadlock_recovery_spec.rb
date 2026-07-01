# frozen_string_literal: true

# Integration coverage for the production failure that stranded branches at
# scale: two advancers each hold a `FOR KEY SHARE` lock on the run row (from
# inserting run-referencing rows in a transition) and both upgrade to
# `FOR UPDATE` in `resolve_terminal_state!`, deadlocking. The deadlock victim's
# transition has already run `complete!`, which nulls the in-memory claim_token;
# the rollback restores the DB token but not the attribute. The advancer must
# still recognize its claim on the error-recovery path, release the branch, and
# complete it on retry — rather than strand it in `advancing` until a reap.
#
# This drives the real advancement machinery (`with_latest_claimed` + `advance!`,
# the exact body of the advancer work loop) so the fence, rollback, rescue,
# release, and re-claim all run for real. Only the deadlock itself is simulated,
# and only on the first resolution, so the retry can complete.
RSpec.describe "Run-row deadlock recovery" do
  let(:pipeline) { create(:pipeline, :in_progress) }
  let(:pipeline_klass) { pipeline.klass }
  let(:run) { create(:run, :in_progress, pipeline:, definition:) }
  let(:branch) { create(:branch, :in_progress, pipeline_klass:, run:) }
  let(:step) { create(:step, :advancing, branch:, run:) }
  let(:definition) do
    {
      nodes: %w[MyStepA.0],
      edges: { "MyStepA.0" => { klass: "MyStepA" } },
    }.to_json
  end

  before do
    create(:process, :current)
    step
  end

  def advance_once
    Ductwork::Branch.with_latest_claimed(pipeline_klass) do |branch, transition, advancement|
      branch.advance!(transition, advancement)
    end
  end

  it "recovers from the deadlock and completes the run instead of stranding the branch" do
    # NOTE: stub the run-row lock itself (`lock_for_terminal_resolution!`) — the
    # exact site the real deadlock fires from inside `resolve_terminal_state!`.
    resolutions = 0
    allow_any_instance_of(Ductwork::Run) # rubocop:disable RSpec/AnyInstance
      .to receive(:lock_for_terminal_resolution!)
      .and_wrap_original do |original, *args|
        resolutions += 1
        if resolutions == 1
          raise ActiveRecord::Deadlocked, "simulated run-row deadlock"
        end

        original.call(*args)
      end

    # First pass: claims the branch, completes it (nulling the in-memory token),
    # then deadlocks resolving the run. It must roll back and release the branch.
    expect(advance_once).to be(true)
    expect(branch.reload.status).to eq("in_progress")
    expect(branch.claim_token).to be_nil
    expect(step.reload.status).to eq("advancing")

    # Second pass: re-claims the released branch and completes it.
    expect(advance_once).to be(true)
    expect(branch.reload.status).to eq("completed")
    expect(run.reload.status).to eq("completed")

    # the branch was retried on the same transition, not stranded
    expect(branch.transitions.sole.advancements.count).to eq(2)
    expect(resolutions).to eq(2)
  end
end
