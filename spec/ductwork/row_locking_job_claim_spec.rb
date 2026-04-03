# frozen_string_literal: true

RSpec.describe Ductwork::RowLockingJobClaim do
  describe "#latest" do
    subject(:claim) { described_class.new(klass) }

    let(:process) { create(:process, :current) }

    before do
      process
    end

    context "when there is a job to claim" do
      let(:availability) { create(:availability) }
      let(:execution) { availability.execution }
      let(:step) { execution.job.step }
      let(:run) { step.run }
      let(:klass) { run.pipeline_klass }

      before do
        availability.update!(pipeline_klass: klass)
      end

      it "returns a job" do
        job = claim.latest

        expect(job).to eq(execution.job)
      end

      it "marks the availability as completed" do
        claim = described_class.new(klass)

        expect do
          claim.latest
        end.to change { availability.reload.completed_at }.from(nil).to(be_almost_now)
      end

      it "marks the step, run, and pipeline as in-progress" do
        claim.latest

        expect(step.reload).to be_in_progress
        expect(run.reload).to be_in_progress
        expect(run.pipeline).to be_in_progress
      end
    end

    context "when there is no job to claim" do
      let(:klass) { "MyPipeline" }

      it "returns nil" do
        job = described_class.new(klass).latest

        expect(job).to be_nil
      end

      it "logs" do
        allow(Ductwork.logger).to receive(:debug).and_call_original

        claim.latest

        expect(Ductwork.logger).to have_received(:debug).with(
          msg: "No available job to claim",
          role: :job_worker,
          process_id: process.id,
          pipeline: klass
        )
      end
    end
  end
end
