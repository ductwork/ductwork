# frozen_string_literal: true

RSpec.describe Ductwork::Branch, "#advance!" do
  subject(:branch) { create(:branch, :claimed, run:) }

  let(:run) { create(:run, status: :in_progress, definition: definition) }
  let(:definition) do
    {
      nodes: %w[MyStepA.0 MyStepB.1],
      edges: {
        "MyStepA.0" => { to: %w[MyStepB.1], type: "chain", klass: "MyStepA" },
        "MyStepB.1" => { klass: "MyStepB" },
      },
    }.to_json
  end
  let(:step) do
    create(
      :step,
      status: step_status,
      node: "MyStepA.0",
      klass: "MyStepA",
      branch: branch,
      run: run
    )
  end
  let(:step_status) { :in_progress }
  let(:transition) do
    create(:transition, branch: branch, in_step: step, out_step: nil, completed_at: nil)
  end
  let(:advancement) { create(:advancement, transition:) }

  before do
    step
    transition
    advancement
    create(:process, :current)
  end

  # NOTE: `BranchClaim`'s claiming UPDATE re-asserts that the branch still has a
  # step in `advancing`/`failed`, so this state should be unreachable in
  # production. These examples pin the backstop behavior anyway: holding a claim
  # on a branch whose latest step is still running must never route (the job has
  # no return value yet, so it would mint a downstream step from nil) and must
  # never halt (there is no failure to attribute).
  context "when the latest step is not done running" do
    it "does not advance the branch" do
      expect do
        branch.advance!(transition, advancement)
      end.to not_change(Ductwork::Step, :count)
        .and not_change(Ductwork::Job, :count)

      expect(step.reload).to be_in_progress
    end

    it "releases the claim back to the branch" do
      branch.advance!(transition, advancement)

      expect(branch.reload).to be_in_progress
      expect(branch.claimed_for_advancing_at).to be_nil
      expect(branch.claim_token).to be_nil
    end

    it "does not halt the branch or the run" do
      branch.advance!(transition, advancement)

      expect(branch.reload).not_to be_halted
      expect(branch.halt_reason).to be_nil
      expect(run.reload).to be_in_progress
    end

    # NOTE: an error_klass here would burn the advancer's retry budget
    # (`too_many_failed_attempts?`) and eventually halt a healthy branch.
    it "closes the transition and advancement without recording an error" do
      branch.advance!(transition, advancement)

      expect(advancement.reload.completed_at).to be_almost_now
      expect(advancement.error_klass).to be_nil
      expect(transition.reload.completed_at).to be_almost_now
    end

    it "logs the released claim" do
      allow(Ductwork.logger).to receive(:warn).and_call_original

      branch.advance!(transition, advancement)

      expect(Ductwork.logger).to have_received(:warn).with(
        msg: "Branch claimed with no step to advance, released",
        branch_id: branch.id,
        step_id: step.id,
        step_status: "in_progress",
        role: :pipeline_advancer
      )
    end

    context "when the advancer crash budget is already exhausted" do
      let(:advancement) { create(:advancement, transition: transition, crash_count: 100) }

      it "still releases rather than halting, since there is nothing to advance" do
        branch.advance!(transition, advancement)

        expect(branch.reload).to be_in_progress
        expect(branch.halt_reason).to be_nil
      end
    end
  end

  Ductwork::Step::ADVANCEABLE_STATUSES.each do |status|
    context "when the latest step is #{status}" do
      let(:step_status) { status }

      it "advances the branch" do
        create(:job, step: step, output_payload: { payload: %w[a b c] }.to_json)

        branch.advance!(transition, advancement)

        expect(branch.reload.claimed_for_advancing_at).to be_nil
        expect(transition.reload.completed_at).to be_almost_now
      end
    end
  end
end
