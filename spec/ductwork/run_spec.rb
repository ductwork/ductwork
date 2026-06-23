# frozen_string_literal: true

RSpec.describe Ductwork::Run do
  describe "validations" do
    let(:pipeline_klass) { "MyPipeline" }
    let(:definition) { JSON.dump({}) }
    let(:definition_sha1) { Digest::SHA1.hexdigest(definition) }
    let(:status) { described_class.statuses.keys.sample }
    let(:triggered_at) { Time.current }
    let(:started_at) { 10.minutes.from_now }

    it "is invalid if pipeline klass is blank" do
      run = described_class.new(
        definition:,
        definition_sha1:,
        status:,
        triggered_at:,
        started_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Pipeline klass can't be blank")
    end

    it "is invalid if definition is blank" do
      run = described_class.new(
        pipeline_klass:,
        definition_sha1:,
        status:,
        triggered_at:,
        started_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Definition can't be blank")
    end

    it "is invalid if definition sha1 is blank" do
      run = described_class.new(
        pipeline_klass:,
        definition:,
        status:,
        triggered_at:,
        started_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Definition sha1 can't be blank")
    end

    it "is invalid if status is blank" do
      run = described_class.new(
        pipeline_klass:,
        definition:,
        definition_sha1:,
        triggered_at:,
        started_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Status can't be blank")
    end

    it "is invalid if triggered at is blank" do
      run = described_class.new(
        pipeline_klass:,
        definition:,
        definition_sha1:,
        status:,
        started_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Triggered at can't be blank")
    end

    it "is invalid if started at is blank" do
      run = described_class.new(
        pipeline_klass:,
        definition:,
        definition_sha1:,
        status:,
        triggered_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Started at can't be blank")
    end

    it "is valid otherwise" do
      run = described_class.new(
        pipeline_klass:,
        definition:,
        definition_sha1:,
        status:,
        triggered_at:,
        started_at:
      )

      expect(run).to be_valid
    end
  end

  describe "#parsed_definition" do
    it "returns a JSON parsed indifferent hash" do
      run = described_class.new(definition: JSON.dump({ foo: "bar" }))

      expect(run.parsed_definition[:foo]).to eq("bar")
      expect(run.parsed_definition["foo"]).to eq("bar")
    end
  end

  describe "#resolve_terminal_state!" do
    subject(:run) { create(:run, :in_progress) }

    let(:pipeline) { run.pipeline.tap(&:in_progress!) }

    before do
      allow(Ductwork.logger).to receive(:info).and_call_original
      allow(Ductwork.logger).to receive(:warn).and_call_original
      pipeline
    end

    it "no-ops if the run is already halted" do
      run.halted!

      expect do
        run.resolve_terminal_state!
      end.not_to change(run, :status)

      expect(pipeline).to be_in_progress
    end

    it "no-ops if the run is already completed" do
      run.completed!

      expect do
        run.resolve_terminal_state!
      end.not_to change(run, :status)

      expect(pipeline).to be_in_progress
    end

    it "no-ops if there are any non-terminal branches" do
      create(:branch, :completed, run:)
      create(:branch, :in_progress, run:)
      create(:branch, :halted, run:)

      expect do
        run.resolve_terminal_state!
      end.not_to change(run, :status)

      expect(pipeline).to be_in_progress
    end

    context "when there are halted branches in the run" do
      before do
        create(:branch, :completed, run:)
        create(:branch, :halted, run:)
        create(:branch, :completed, run:)
      end

      it "halts the run and pipeline when any branch is halted" do
        run.resolve_terminal_state!

        expect(pipeline.reload).to be_halted
      end

      it "logs" do
        run.resolve_terminal_state!

        expect(Ductwork.logger).to have_received(:warn).with(
          msg: "Pipeline halted",
          pipeline_id: pipeline.id,
          run_id: run.id
        )
      end
    end

    context "when all branches successfully completed" do
      before do
        create(:branch, :completed, run:)
        create(:branch, :completed, run:)
      end

      it "completes the run and pipeline" do
        expect do
          run.resolve_terminal_state!
        end.to change(run, :status).from("in_progress").to("completed")
          .and change(run, :completed_at).to(be_almost_now)

        expect(pipeline.reload).to be_completed
      end

      it "logs" do
        run.resolve_terminal_state!

        expect(Ductwork.logger).to have_received(:info).with(
          msg: "Pipeline completed",
          pipeline_id: pipeline.id,
          run_id: run.id
        )
      end
    end
  end

  describe "#dispatch_on_halt!" do
    subject(:run) { create(:run, :halted, definition:) }

    let(:definition) { { metadata: { on_halt: { klass: "MyHaltStep" } } }.to_json }
    let(:halt_step) { instance_double(MyHaltStep, execute: nil) }

    before do
      create(:branch, :halted, run:)
      allow(MyHaltStep).to receive(:new).and_return(halt_step)
    end

    it "runs the handler with the branch halt reasons" do
      run.dispatch_on_halt!

      expect(MyHaltStep).to have_received(:new).with(["advancer_retries_exhausted"])
      expect(halt_step).to have_received(:execute)
    end

    it "claims the dispatch" do
      expect do
        run.dispatch_on_halt!
      end.to change { run.reload.on_halt_dispatched_at }.from(nil).to(be_almost_now)
    end

    it "runs the handler at most once across repeated calls" do
      run.dispatch_on_halt!
      run.dispatch_on_halt!

      expect(MyHaltStep).to have_received(:new).once
    end

    it "does nothing when the run is not halted" do
      run.update!(status: "in_progress")

      run.dispatch_on_halt!

      expect(MyHaltStep).not_to have_received(:new)
      expect(run.reload.on_halt_dispatched_at).to be_nil
    end

    context "when no `on_halt` handler is configured" do
      let(:definition) { JSON.dump({}) }

      it "does nothing" do
        run.dispatch_on_halt!

        expect(run.reload.on_halt_dispatched_at).to be_nil
      end
    end

    context "when the handler raises" do
      before do
        allow(halt_step).to receive(:execute).and_raise("boom")
        allow(Ductwork.logger).to receive(:error)
      end

      it "isolates the error and logs" do
        expect { run.dispatch_on_halt! }.not_to raise_error

        expect(Ductwork.logger).to have_received(:error).with(
          hash_including(msg: "on_halt handler errored", run_id: run.id)
        )
      end
    end
  end
end
