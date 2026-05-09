# frozen_string_literal: true

RSpec.describe Ductwork::OptimisticLockingExecutionClaim do
  describe "#latest" do
    subject(:claim) { described_class.new(klass, process.id) }

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

      it "returns the execution" do
        expect(claim.latest).to eq(execution)
      end

      it "marks the availability as completed and assigns the process" do
        expect do
          claim.latest
        end.to change { availability.reload.completed_at }.from(nil).to(be_almost_now)
          .and change(availability, :process_id).from(nil).to(process.id)
      end

      it "assigns the process to the execution" do
        expect do
          claim.latest
        end.to change { execution.reload.process_id }.from(nil).to(process.id)
      end

      it "moves the step, run, and pipeline from waiting to in-progress" do
        step.update!(status: "waiting")
        run.update!(status: "waiting")
        run.pipeline.update!(status: "waiting")

        expect do
          claim.latest
        end.to change { run.pipeline.reload.status }.from("waiting").to("in_progress")
          .and change { run.reload.status }.from("waiting").to("in_progress")
          .and change { step.reload.status }.from("waiting").to("in_progress")
      end

      it "only claims availabilities for the specified pipeline klass" do
        other_availability = create(:availability)

        expect do
          claim.latest
        end.not_to change { other_availability.reload.process_id }.from(nil)
      end

      it "does not claim availabilities scheduled in the future" do
        future_availability = create(:availability, started_at: 5.seconds.from_now, pipeline_klass: klass)

        expect do
          claim.latest
        end.not_to change { future_availability.reload.completed_at }.from(nil)
      end
    end

    context "when there is no job to claim" do
      let(:klass) { "MyPipeline" }

      it "returns nil" do
        expect(claim.latest).to be_nil
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
