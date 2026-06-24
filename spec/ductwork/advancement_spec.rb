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

  describe "#crash?" do
    it "is true for a process crash" do
      advancement = build(:advancement, error_klass: "Ductwork::ProcessCrash")

      expect(advancement).to be_crash
    end

    it "is true for a thread crash" do
      advancement = build(:advancement, error_klass: "Ductwork::ThreadCrash")

      expect(advancement).to be_crash
    end

    it "is false for a non-crash logic error" do
      advancement = build(:advancement, :errored)

      expect(advancement).not_to be_crash
    end

    it "is false when there is no error" do
      advancement = build(:advancement)

      expect(advancement).not_to be_crash
    end
  end

  describe "#process_crashed!" do
    subject(:advancement) { described_class.create!(transition:, started_at:) }

    let(:started_at) { Time.current }
    let(:branch) { create(:branch, :claimed) }
    let(:transition) { create(:transition, branch:) }

    # NOTE: this protects against a worker racing against the reaper where an
    # advancement can be incomplete at read-time but completed by write-time
    it "no-ops if the advancement is completed" do
      advancement.update!(completed_at: Time.current)

      expect do
        advancement.process_crashed!
      end.to not_change(advancement, :completed_at)
    end

    it "is idempotent" do
      advancement.process_crashed!

      expect do
        advancement.process_crashed!
      end.to not_change(advancement, :completed_at)
    end

    it "sets error metadata on itself" do
      expect do
        advancement.process_crashed!
      end.to change { advancement.reload.completed_at }.from(nil).to(be_almost_now)
        .and change(advancement, :error_klass).to("Ductwork::ProcessCrash")
        .and change(advancement, :error_message).to("Reaped from orphaned process")
    end

    it "releases the branch" do
      expect do
        advancement.process_crashed!
      end.to change { branch.reload.claimed_for_advancing_at }.to(nil)
        .and change(branch, :last_advanced_at).to(be_almost_now)
        .and change(branch, :status).to("in_progress")
    end
  end

  describe "#thread_crashed!" do
    subject(:advancement) { described_class.create!(transition:, started_at:) }

    let(:started_at) { Time.current }
    let(:branch) { create(:branch, :claimed) }
    let(:transition) { create(:transition, branch:) }
    let(:token) { branch.claim_token }

    # NOTE: this protects against a worker racing against the reaper where an
    # advancement can be incomplete at read-time but completed by write-time
    it "no-ops if the advancement is completed" do
      advancement.update!(completed_at: Time.current)

      expect do
        advancement.thread_crashed!(token)
      end.to not_change(advancement, :completed_at)
    end

    it "is idempotent" do
      advancement.thread_crashed!(token)

      expect do
        advancement.thread_crashed!(token)
      end.to not_change(advancement, :completed_at)
    end

    it "completes and sets thread crash error metadata" do
      expect do
        advancement.thread_crashed!(token)
      end.to change { advancement.reload.completed_at }.from(nil).to(be_almost_now)
        .and change(advancement, :error_klass).to("Ductwork::ThreadCrash")
        .and change(advancement, :error_message).to(
          "Advancement abandoned from a thread crash"
        )
    end

    it "releases the branch" do
      expect do
        advancement.thread_crashed!(token)
      end.to change { branch.reload.claimed_for_advancing_at }.to(nil)
        .and change(branch, :last_advanced_at).to(be_almost_now)
        .and change(branch, :status).to("in_progress")
    end

    it "does not release the branch when the claim token diverges" do
      expect do
        advancement.thread_crashed!(SecureRandom.uuid)
      end.to not_change { branch.reload.claimed_for_advancing_at }
        .and not_change(branch, :status)
    end
  end
end
