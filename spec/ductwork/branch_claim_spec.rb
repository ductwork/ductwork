# frozen_string_literal: true

RSpec.describe Ductwork::BranchClaim do
  describe "#latest" do
    subject(:claim) { described_class.new(pipeline_klass) }

    let(:pipeline_klass) { "MyPipeline" }
    let(:branch) { create(:branch, :in_progress, pipeline_klass:) }

    context "when there is a branch to claim" do
      before do
        create(:process, :current)
        create(:step, :advancing, branch:)
        create(:branch, :in_progress, pipeline_klass: "OtherPipeline")
        create(:branch, :in_progress, claimed_for_advancing_at: Time.current)
        create(:branch, status: "advancing")
        create(:branch, :in_progress, last_advanced_at: 1.minute.from_now)
      end

      it "returns the latest branch" do
        record = claim.latest

        expect(record).to eq(branch)
      end

      it "sets the transition and advancement" do
        claim.latest

        expect(claim.transition).to eq(Ductwork::Transition.sole)
        expect(claim.advancement).to eq(Ductwork::Advancement.sole)
      end

      it "attaches the advancement to the current process record" do
        claim.latest

        expect(claim.advancement.process).to eq(Ductwork::Process.current)
      end

      it "generates and sets the claim token" do
        uuid = "9c1c9728-485b-4ca6-bb68-18d5678dd4ed"
        allow(SecureRandom).to receive(:uuid).and_return(uuid)

        record = claim.latest

        expect(claim.token).to eq(uuid)
        expect(record.claim_token).to eq(uuid)
      end

      it "sets the branch status and claim state" do
        record = claim.latest

        expect(record).to be_advancing
        expect(record.claimed_for_advancing_at).to be_almost_now
      end

      context "when competing advancers win the race on other sampled candidates" do
        let!(:stolen_branches) do
          Array.new(2) do
            other = create(:branch, :in_progress, pipeline_klass:)
            create(:step, :advancing, branch: other)
            other
          end
        end

        before do
          # NOTE: simulates competing advancers claiming candidates between our
          # window `SELECT` and our claiming `UPDATE`s, leaving exactly one
          # survivor. Whichever position the survivor lands in the sample, the
          # walk has to reach it instead of giving up on the first lost race --
          # the sample is randomized, so the assertion holds for every ordering.
          allow(Ductwork::FaultInjection).to receive(:checkpoint) do |key|
            if key == :after_branch_candidate_select
              Ductwork::Branch
                .where(id: stolen_branches.map(&:id))
                .update_all(
                  claimed_for_advancing_at: Time.current,
                  status: "advancing"
                )
            end
          end
        end

        it "keeps walking the sample and claims the surviving branch" do
          record = claim.latest

          expect(record).to eq(branch)
          expect(record).to be_advancing
          expect(record.claim_token).to eq(claim.token)
        end

        it "sets up the transition and advancement for the surviving branch" do
          claim.latest

          expect(claim.transition.branch).to eq(branch)
          expect(claim.advancement).to eq(Ductwork::Advancement.sole)
        end
      end

      context "when competing advancers win the race on every sampled candidate" do
        before do
          allow(Ductwork::FaultInjection).to receive(:checkpoint) do |key|
            if key == :after_branch_candidate_select
              Ductwork::Branch
                .where(pipeline_klass:)
                .update_all(
                  claimed_for_advancing_at: Time.current,
                  status: "advancing"
                )
            end
          end
        end

        it "returns nil without creating a transition or advancement" do
          expect do
            expect(claim.latest).to be_nil
          end.to not_change(Ductwork::Advancement, :count)
            .and not_change(Ductwork::Transition, :count)
        end

        it "logs the lost races" do
          allow(Ductwork.logger).to receive(:debug).and_call_original

          claim.latest

          expect(Ductwork.logger).to have_received(:debug).with(
            msg: "Did not claim branch, lost races on all sampled IDs",
            pipeline_klass: pipeline_klass,
            role: :pipeline_advancer
          )
        end
      end

      context "when the branch's latest step is failed" do
        before do
          Ductwork::Step.where(branch:).destroy_all
          create(:step, :failed, branch:)
        end

        it "returns the branch" do
          record = claim.latest

          expect(record).to eq(branch)
        end
      end

      context "when there are orphaned advancements" do
        let(:transition) { create(:transition, branch:) }
        let(:advancement) { create(:advancement, transition:) }

        before do
          advancement
        end

        it "fails any abandoned advancement record and creates a new one" do
          claim.latest

          expect(advancement.reload.completed_at).to be_within(1.second).of(Time.current)
          expect(advancement.error_klass).to eq("Ductwork::ProcessCrash")
          expect(advancement.error_message).to eq("Advancement was abandoned from a process crash")
        end
      end

      context "when there is no prior advancement" do
        it "starts the crash count at zero" do
          claim.latest

          expect(claim.advancement.crash_count).to eq(0)
        end
      end

      # NOTE: pin the reused transition to this branch (in_step on it, no
      # out_step) so the transition factory does not spin up extra branches that
      # could compete for the claim and make the assertions flaky.
      context "when the prior advancement on the transition was a crash" do
        let(:transition) do
          in_step = create(:step, :advancing, branch:)

          create(
            :transition,
            branch: branch,
            in_step: in_step,
            out_step: nil,
            completed_at: nil
          )
        end

        before do
          create(:advancement, :crashed, transition: transition, crash_count: 2)
        end

        it "carries the crash count forward and increments it" do
          claim.latest

          expect(claim.advancement.crash_count).to eq(3)
        end
      end

      context "when the prior advancement was an abandoned in-flight crash" do
        let(:transition) do
          in_step = create(:step, :advancing, branch:)

          create(
            :transition,
            branch: branch,
            in_step: in_step,
            out_step: nil,
            completed_at: nil
          )
        end

        before do
          create(:advancement, transition: transition, crash_count: 1)
        end

        it "increments the crash count after the abandonment is stamped" do
          claim.latest

          expect(claim.advancement.crash_count).to eq(2)
        end
      end

      context "when the prior advancement was a non-crash logic error" do
        let(:transition) do
          in_step = create(:step, :advancing, branch:)

          create(
            :transition,
            branch: branch,
            in_step: in_step,
            out_step: nil,
            completed_at: nil
          )
        end

        before do
          create(:advancement, :errored, transition: transition, completed_at: Time.current, crash_count: 2)
        end

        it "carries the crash count forward unchanged" do
          claim.latest

          expect(claim.advancement.crash_count).to eq(2)
        end
      end
    end

    context "when there is no branch to claim" do
      before { create(:process, :current) }

      it "returns nil" do
        record, = claim.latest

        expect(record).to be_nil
      end
    end

    context "when there is no live process record" do
      before do
        create(:step, :advancing, branch:)
      end

      it "returns nil without claiming the branch" do
        record = claim.latest

        expect(record).to be_nil
        expect(branch.reload).to be_in_progress
        expect(branch.claimed_for_advancing_at).to be_nil
      end

      it "does not create an advancement or transition" do
        expect do
          claim.latest
        end.to not_change(Ductwork::Advancement, :count)
          .and not_change(Ductwork::Transition, :count)
      end
    end

    context "when the process record is reaped mid-claim" do
      before do
        create(:step, :advancing, branch:)
        process = create(:process, :current)

        # NOTE: simulates the reaper destroying our own process record between
        # `Process.current` returning it and `transition.advancements.create!`
        # referencing it -- `delete_all` bypasses `dependent: :nullify` (no
        # advancement exists yet to nullify), leaving the FK check on the
        # subsequent insert to fail exactly like a real concurrent reap would.
        allow(Ductwork::FaultInjection).to receive(:checkpoint) do |key|
          Ductwork::Process.where(id: process.id).delete_all if key == :before_advancement_create
        end
      end

      it "returns nil instead of raising" do
        expect(claim.latest).to be_nil
      end

      it "does not leave the branch claimed or a partial transition/advancement behind" do
        claim.latest

        expect(branch.reload).to be_in_progress
        expect(branch.claimed_for_advancing_at).to be_nil
        expect(Ductwork::Transition.count).to eq(0)
        expect(Ductwork::Advancement.count).to eq(0)
      end

      it "logs the lost race with context" do
        allow(Ductwork.logger).to receive(:warn).and_call_original

        claim.latest

        expect(Ductwork.logger).to have_received(:warn).with(
          msg: "Did not claim branch, our process record was reaped mid-claim",
          branch_id: branch.id,
          pipeline_klass: pipeline_klass,
          error_klass: "ActiveRecord::InvalidForeignKey",
          error_message: an_instance_of(String),
          role: :pipeline_advancer
        )
      end
    end

    describe "candidate window sizing" do
      subject(:window_size) { claim.send(:candidate_window_size) }

      before do
        allow(Ductwork.configuration)
          .to receive(:pipeline_advancer_count)
          .with(pipeline_klass)
          .and_return(advancer_count)
      end

      context "with a pool between the floor and the ceiling" do
        let(:advancer_count) { 10 }

        it "derives the window from the advancer pool" do
          expect(window_size).to eq(40)
        end
      end

      context "with a small pool" do
        let(:advancer_count) { 1 }

        it "floors the window so multi-process contention still spreads" do
          expect(window_size).to eq(20)
        end
      end

      context "with a large pool" do
        let(:advancer_count) { 200 }

        it "caps the window so the plucked ID array stays small" do
          expect(window_size).to eq(100)
        end
      end

      context "when read more than once" do
        let(:advancer_count) { 10 }

        it "only reads the configuration once" do
          2.times { claim.send(:candidate_window_size) }

          expect(Ductwork.configuration)
            .to have_received(:pipeline_advancer_count)
            .once
        end
      end
    end
  end
end
