# frozen_string_literal: true

RSpec.describe Ductwork::ClaimedState do
  describe ".mark_in_progress!" do
    subject(:mark_in_progress!) { described_class.mark_in_progress!(step) }

    let(:pipeline) { create(:pipeline, status: "waiting") }
    let(:run) { create(:run, pipeline: pipeline, status: "waiting") }
    let(:step) { create(:step, run: run, status: "waiting") }

    def updates_issued
      statements = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        statements << payload[:sql] if payload[:sql].match?(/\AUPDATE/i)
      end

      yield

      statements
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "moves the step, run, and pipeline to in-progress" do
      expect { mark_in_progress! }
        .to change { step.reload.status }.from("waiting").to("in_progress")
        .and change { run.reload.status }.from("waiting").to("in_progress")
        .and change { pipeline.reload.status }.from("waiting").to("in_progress")
    end

    context "when the run and pipeline are already in progress" do
      let(:pipeline) { create(:pipeline, status: "in_progress") }
      let(:run) { create(:run, pipeline: pipeline, status: "in_progress") }

      it "leaves them in progress" do
        expect { mark_in_progress! }
          .to not_change { run.reload.status }.from("in_progress")
          .and not_change { pipeline.reload.status }.from("in_progress")
      end

      # NOTE: the run and pipeline rows are shared by every step of the run, so
      # even a no-op `UPDATE` here serializes concurrent claims on two rows
      # under InnoDB's REPEATABLE READ locking. Steady state must issue no write
      # against them at all.
      it "does not write to the shared run and pipeline rows" do
        step

        statements = updates_issued { mark_in_progress! }

        expect(statements.grep(/ductwork_runs/)).to be_empty
        expect(statements.grep(/ductwork_pipelines/)).to be_empty
      end

      it "still moves the step to in-progress" do
        expect { mark_in_progress! }.to change { step.reload.status }.from("waiting").to("in_progress")
      end
    end

    context "when the run is not visible" do
      let(:step) { Ductwork::Step.new(id: SecureRandom.uuid, run_id: SecureRandom.uuid) }

      it "does not raise or touch the pipelines table" do
        statements = updates_issued do
          expect { mark_in_progress! }.not_to raise_error
        end

        expect(statements.grep(/ductwork_pipelines/)).to be_empty
      end
    end
  end
end
