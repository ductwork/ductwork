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

    it "locks the branch" do
      branch = instance_double(Ductwork::Branch, lock!: nil, release!: nil)

      allow(transition).to receive(:branch).and_return(branch)

      advancement.abandon!

      expect(branch).to have_received(:lock!)
    end

    # NOTE: this protects against a worker racing against the reaper where an
    # advancement can be incomplete at read-time but completed by write-time
    it "no-ops if the advancement is completed" do
      advancement.update!(completed_at: Time.current)

      expect do
        advancement.abandon!
      end.to not_change(advancement, :completed_at)
    end

    it "sets error metadata on itself" do
      expect do
        advancement.abandon!
      end.to change(advancement, :completed_at).from(nil).to(be_almost_now)
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
end
