# frozen_string_literal: true

RSpec.describe Ductwork::BranchClaim do
  describe "#latest" do
    subject(:claim) { described_class.new(pipeline_klass) }

    let(:pipeline_klass) { "MyPipeline" }
    let(:branch) { create(:branch, :in_progress, pipeline_klass:) }

    context "when there is a branch to claim" do
      before do
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

      it "sets the branch status to advancing" do
        record, = claim.latest

        expect(record).to be_advancing
        expect(record.claimed_for_advancing_at).to be_present
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
    end

    context "when there is no branch to claim" do
      it "returns nil" do
        record, = claim.latest

        expect(record).to be_nil
      end
    end
  end
end
