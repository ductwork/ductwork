# frozen_string_literal: true

RSpec.describe Ductwork::Advancement do
  describe "validations" do
    it "is invalid if started_at is blank" do
      advancement = described_class.new

      expect(advancement).not_to be_valid
      expect(advancement.errors.full_messages.sole).to eq("Started at can't be blank")
    end

    it "is valid otherwise" do
      advancement = described_class.new(started_at: Time.current)

      expect(advancement).to be_valid
    end
  end

  describe "#abandon!" do
    subject(:advancement) { described_class.create!(transition:, started_at:) }

    let(:started_at) { Time.current }
    let(:branch) { create(:branch, :claimed) }
    let(:transition) { create(:transition, branch:) }

    # NOTE: this protects against a worker racing against the reaper where an
    # advancement can be incomplete at read-time but completed by write-time
    it "no-ops if the advancement is completed" do
      advancement.update!(completed_at: Time.current)

      expect do
        advancement.abandon!
      end.to not_change(advancement, :completed_at)
    end

    it "is idempotent" do
      advancement.abandon!

      expect do
        advancement.abandon!
      end.to not_change(advancement, :completed_at)
    end

    it "sets error metadata on itself" do
      expect do
        advancement.abandon!
      end.to change { advancement.reload.completed_at }.from(nil).to(be_almost_now)
        .and change(advancement, :error_klass).to("Ductwork::ProcessCrash")
        .and change(advancement, :error_message).to("Reaped from orphaned process")
    end

    it "releases the branch" do
      expect do
        advancement.abandon!
      end.to change { branch.reload.claimed_for_advancing_at }.to(nil)
        .and change(branch, :last_advanced_at).to(be_almost_now)
        .and change(branch, :status).to("in_progress")
    end
  end

  describe "#thread_crashed!" do
    subject(:advancement) { described_class.create!(transition:, started_at:) }

    let(:started_at) { Time.current }
    let(:transition) { create(:transition) }

    it "completes and sets thread crash error metadata" do
      expect do
        advancement.thread_crashed!
      end.to change(advancement, :completed_at).from(nil).to(be_almost_now)
        .and change(advancement, :error_klass).to("Ductwork::ThreadCrash")
        .and change(advancement, :error_message).to(
          "Advancement abandoned from a thread crash"
        )
    end
  end
end
