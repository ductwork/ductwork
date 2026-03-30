# frozen_string_literal: true

RSpec.describe Ductwork::Branch do
  describe "validations" do
    let(:pipeline_klass) { "MyPipeline" }
    let(:last_advanced_at) { Time.current }
    let(:status) { described_class.statuses.keys.sample }
    let(:started_at) { Time.current }

    it "is invalid if the `pipeline_klass` is not present" do
      branch = described_class.new(
        last_advanced_at:,
        status:,
        started_at:
      )
      branch.pipeline_klass = "                    "

      expect(branch).not_to be_valid
      expect(branch.errors.full_messages.sole).to eq("Pipeline klass can't be blank")
    end

    it "is invalid if the `last_advanced_at` is not present" do
      branch = described_class.new(
        pipeline_klass:,
        status:,
        started_at:
      )

      expect(branch).not_to be_valid
      expect(branch.errors.full_messages.sole).to eq("Last advanced at can't be blank")
    end

    it "is invalid if `status` is not present" do
      branch = described_class.new(
        pipeline_klass:,
        last_advanced_at:,
        started_at:
      )
      branch.status = "\n\n\n\n\n"

      expect(branch).not_to be_valid
      expect(branch.errors.full_messages.sole).to eq("Status can't be blank")
    end

    it "is invalid if `started_at` is not present" do
      branch = described_class.new(
        pipeline_klass:,
        last_advanced_at:,
        status:
      )

      expect(branch).not_to be_valid
      expect(branch.errors.full_messages.sole).to eq("Started at can't be blank")
    end

    it "is valid otherwise" do
      branch = described_class.new(
        pipeline_klass:,
        last_advanced_at:,
        status:,
        started_at:
      )

      expect(branch).to be_valid
    end
  end

  describe ".with_latest_claimed" do
    let(:pipeline_klass) { "MyPipeline" }
    let(:claim) do
      instance_double(
        Ductwork::BranchClaim,
        latest: branch,
        transition: transition,
        advancement: advancement
      )
    end
    let(:branch) do
      create(
        :branch,
        claimed_for_advancing_at: Time.current,
        status: "advancing",
        last_advanced_at: 5.minutes.ago
      )
    end
    let(:transition) { create(:transition, branch:) }
    let(:advancement) { create(:advancement, transition:) }

    before do
      allow(Ductwork::BranchClaim).to receive(:new).and_return(claim)
    end

    it "calls the branch claim service" do
      described_class.with_latest_claimed(pipeline_klass) {}

      expect(Ductwork::BranchClaim).to have_received(:new).with(pipeline_klass)
      expect(claim).to have_received(:latest)
    end

    it "yields the claimed branch" do
      expect do |block|
        described_class.with_latest_claimed(pipeline_klass, &block)
      end.to yield_with_args(branch, transition, advancement)
    end

    it "does not yield if there is no branch to claim" do
      claim = instance_double(Ductwork::BranchClaim, latest: nil)
      allow(Ductwork::BranchClaim).to receive(:new).and_return(claim)

      expect do |block|
        described_class.with_latest_claimed(pipeline_klass, &block)
      end.not_to yield_control
    end

    it "releases the claim on the branch" do
      branch.save!

      expect do
        described_class.with_latest_claimed(pipeline_klass) {}
      end.to change { branch.reload.claimed_for_advancing_at }.to(nil)
        .and change(branch, :last_advanced_at).to(be_within(1.second).of(Time.current))
        .and change(branch, :status).from("advancing").to("in_progress")
    end
  end

  # NOTE: the rest of the specs are in their own files by transition type
  describe "#advance!" do
    subject(:branch) { create(:branch) }

    let(:step) { create(:step, :advancing, branch:) }

    before do
      step
      create(:process, :current)
    end

    it "completes the step" do
      expect do
        branch.advance!(spy, spy)
      end.to change { step.reload.status }.from("advancing").to("completed")
        .and change(step, :completed_at).from(nil).to(be_almost_now)
    end

    context "when the step is the last node" do
      let(:pipeline) do
        branch.pipeline.tap do |p|
          p.in_progress!
          p.update!(definition:)
        end
      end

      let(:definition) do
        {
          nodes: %w[MyStepA.0],
          edges: {
            "MyStepA.0" => { klass: "MyStepA" },
          },
        }.to_json
      end

      it "completes the branch" do
        expect do
          branch.advance!(spy, spy)
        end.to change { branch.reload.completed_at }.to(be_almost_now)
      end

      it "completes the pipeline" do
        expect do
          branch.advance!(spy, spy)
        end.to change { pipeline.reload.status }.to("completed")
          .and change(pipeline, :completed_at).to(be_almost_now)
      end
    end

    context "when there are other active branches" do
      let(:pipeline) do
        branch.pipeline.tap do |p|
          p.in_progress!
          p.update!(definition:)
        end
      end

      let(:definition) do
        {
          nodes: %w[MyStepA.0],
          edges: {
            "MyStepA.0" => { klass: "MyStepA" },
          },
        }.to_json
      end

      before do
        create(:branch, :in_progress, pipeline:)
      end

      it "does not complete the pipeline" do
        expect do
          branch.advance!(spy, spy)
        end.not_to change(pipeline, :status)
      end
    end

    context "when there is an in-progress transition" do
      let(:definition) do
        {
          nodes: %w[MyStepA.0],
          edges: {
            "MyFirstStep.0" => { klass: "MyFirstStep" },
          },
        }.to_json
      end
      let(:transition) do
        create(
          :transition,
          in_step: step,
          out_step: nil,
          branch: branch
        )
      end
      let(:advancement) { create(:advancement, transition:) }

      before do
        branch.pipeline.tap do |p|
          p.in_progress!
          p.update!(definition:)
        end
        # previous steps and transition
        in_step = create(:step, :completed, started_at: 1.hour.ago, branch: branch)
        out_step = create(:step, :completed, started_at: 1.hour.ago, branch: branch)
        create(
          :transition,
          started_at: 1.hour.ago,
          completed_at: 1.minute.ago,
          in_step: in_step,
          out_step: out_step,
          branch: branch
        )
      end

      it "attempts to advance again and completes the transition" do
        expect do
          branch.advance!(transition, advancement)
        end.to change { transition.reload.completed_at }.to(be_almost_now)
      end
    end

    context "when the advancing errors" do
      let(:definition) do
        {
          nodes: %w[MyFirstStep.0],
          edges: {
            "MyFirstStep.0" => { to: %w[MySecondStep.1], type: "bogus" },
          },
        }.to_json
      end
      let(:transition) { create(:transition, branch:) }
      let(:advancement) { create(:advancement, transition:) }

      before do
        branch.pipeline.tap do |p|
          p.in_progress!
          p.update!(definition:)
        end
      end

      it "completes and sets error metadata on the advancement record" do
        branch.advance!(transition, advancement)

        advancement = branch.transitions.sole.advancements.sole
        expect(advancement.completed_at).to be_almost_now
        expect(advancement.error_klass).to eq("Ductwork::Branch::TransitionError")
        expect(advancement.error_message).to eq("Invalid transition type `bogus`")
        expect(advancement.error_backtrace).to be_present
      end

      it "logs" do
        allow(Ductwork.logger).to receive(:error)

        branch.advance!(transition, advancement)

        expect(Ductwork.logger).to have_received(:error).with(
          msg: "Branch advancement errored",
          branch_id: branch.id,
          error_klass: "Ductwork::Branch::TransitionError",
          error_message: "Invalid transition type `bogus`"
        )
      end
    end
  end

  describe "#complete!" do
    subject(:branch) do
      create(:branch, :in_progress, claimed_for_advancing_at: Time.current)
    end

    it "sets the status and timestamp for the branch" do
      expect do
        branch.complete!
      end.to change(branch, :status).from("in_progress").to("completed")
        .and change(branch, :completed_at).to(be_within(1.second).of(Time.current))
    end

    it "releases the branch" do
      expect do
        branch.complete!
      end.to change(branch, :claimed_for_advancing_at).to(nil)
        .and change(branch, :last_advanced_at).to be_almost_now
    end

    it "logs" do
      allow(Ductwork.logger).to receive(:info).and_call_original

      branch.complete!

      expect(Ductwork.logger).to have_received(:info).with(
        msg: "Branch completed",
        branch_id: branch.id,
        role: :pipeline_advancer
      )
    end
  end

  describe "#halt!" do
    subject(:branch) { create(:branch, :in_progress) }

    it "sets the status and timestamp for the branch" do
      expect do
        branch.halt!
      end.to change(branch, :status).from("in_progress").to("halted")
    end

    it "logs" do
      allow(Ductwork.logger).to receive(:info).and_call_original

      branch.halt!

      expect(Ductwork.logger).to have_received(:info).with(
        msg: "Branch halted",
        branch_id: branch.id,
        role: :pipeline_advancer
      )
    end
  end

  describe "#latest_step" do
    subject(:branch) { create(:branch) }

    let(:started_at) { Time.current }
    let(:latest_step) { create(:step, started_at:, branch:) }

    before do
      latest_step
      create(:step, started_at: 10.minutes.ago, branch: branch)
    end

    it "returns the latest step" do
      expect(branch.latest_step).to eq(latest_step)
    end
  end

  describe "#release!" do
    subject(:branch) do
      create(
        :branch,
        :advancing,
        claimed_for_advancing_at: Time.current
      )
    end

    it "nullifies the claim timestamp and sets status and last advanced at" do
      expect do
        branch.release!
      end.to change { branch.reload.status }.to("in_progress")
        .and change(branch, :claimed_for_advancing_at).to(nil)
        .and change(branch, :last_advanced_at).to be_almost_now
    end
  end
end
