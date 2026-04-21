# frozen_string_literal: true

RSpec.describe Ductwork::Process do
  let(:pid) { ::Process.pid }
  let(:machine_identifier) do
    File.read("/etc/machine-id").strip
  rescue Errno::ENOENT
    Socket.gethostname
  end
  let(:other_process) do
    machine_identifier = "foobar"

    described_class.create!(
      pid:,
      machine_identifier:,
      last_heartbeat_at:
    )
  end

  describe "validations" do
    let(:last_heartbeat_at) { Time.current }

    it "is invalid if pid and machine identifier are not unique" do
      described_class.create!(pid:, machine_identifier:, last_heartbeat_at:)

      process = described_class.new(pid:, machine_identifier:, last_heartbeat_at:)

      expect(process).not_to be_valid
      expect(process.errors.full_messages).to eq(["Pid has already been taken"])
    end

    it "is valid otherwise" do
      other_process

      process = described_class.new(pid:, machine_identifier:, last_heartbeat_at:)

      expect(process).to be_valid
    end
  end

  describe ".adopt_or_create_current!" do
    it "creates a new process record" do
      record = nil

      expect do
        record = described_class.adopt_or_create_current!
      end.to change(described_class, :count).by(1)

      expect(record.pid).to eq(::Process.pid)
      expect(record.machine_identifier).to eq(Ductwork::MachineIdentifier.fetch)
      expect(record.last_heartbeat_at).to be_almost_now
    end

    it "returns an existing process record" do
      existing_record = create(:process, :current)

      record = described_class.adopt_or_create_current!

      expect(record).to eq(existing_record)
    end

    it "updates the last heart timestamp" do
      existing_record = create(:process, :current)

      expect do
        described_class.adopt_or_create_current!
      end.to change { existing_record.reload.last_heartbeat_at }.to(be_almost_now)
    end
  end

  describe ".current" do
    let(:last_heartbeat_at) { Time.current }

    it "returns the process by PID and machine identifier" do
      process = described_class.create!(
        pid:,
        machine_identifier:,
        last_heartbeat_at:
      )

      expect(described_class.current).to eq(process)
    end

    it "returns nil if no record exists" do
      expect(described_class.current).to be_nil
    end
  end

  describe ".reap_all!" do
    it "releases associated incomplete branch advancements" do
      process = create(:process, last_heartbeat_at: 2.minutes.ago)
      advancement = create(:advancement, process:)
      branch = advancement.transition.branch.tap do |b|
        b.update!(claimed_for_advancing_at: Time.current)
      end

      expect do
        described_class.reap_all!(:thread_supervisor)
      end.to change { branch.reload.claimed_for_advancing_at }.to(nil)
    end

    it "re-enqueues claimed jobs with incomplete executions" do
      process = create(:process, last_heartbeat_at: 2.minutes.ago)
      availability = create(:availability, process: process, completed_at: Time.current)
      execution = availability.execution

      described_class.reap_all!(:thread_supervisor)

      expect(execution.reload.completed_at).to be_present
      expect(execution.result.result_type).to eq("process_crashed")

      new_execution = execution.job.executions.where.not(id: execution.id).sole
      expect(new_execution.retry_count).to eq(execution.retry_count)
      expect(new_execution.availability).to be_present
      expect(new_execution.availability.completed_at).to be_nil
    end

    it "deletes old process records" do
      old_record = create(:process, last_heartbeat_at: 2.minutes.ago)
      _new_record = create(:process)

      expect do
        described_class.reap_all!(:thread_supervisor)
      end.to change(described_class, :count).by(-1)

      expect do
        old_record.reload
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "logs" do
      create(:process, last_heartbeat_at: 2.minutes.ago)
      allow(Ductwork.logger).to receive(:debug).and_call_original

      described_class.reap_all!(:process_supervisor)

      expect(Ductwork.logger).to have_received(:debug).with(
        msg: "Reaping orphaned process records",
        role: :process_supervisor
      )
      expect(Ductwork.logger).to have_received(:debug).with(
        msg: "Reaped 1 orphaned process records",
        count: 1,
        role: :process_supervisor
      )
    end
  end

  describe ".report_heartbeat!" do
    it "updates the heartbeat timestamp" do
      last_heartbeat_at = 1.day.ago
      process = described_class.create!(
        pid:,
        machine_identifier:,
        last_heartbeat_at:
      )

      expect do
        described_class.report_heartbeat!
      end.to change { process.reload.last_heartbeat_at }.to(
        be_within(1.second).of(Time.current)
      )
    end

    it "queries the record by pid and machine identifier" do
      described_class.create!(
        pid: pid,
        machine_identifier: "foobar",
        last_heartbeat_at: 1.day.ago
      )
      process = described_class.create!(
        pid: pid,
        machine_identifier: machine_identifier,
        last_heartbeat_at: 1.day.ago
      )

      described_class.report_heartbeat!

      expect(process.reload.last_heartbeat_at).to be_within(1.second).of(Time.current)
    end

    it "re-adopts and logs a warning if the record does not exist" do
      allow(Ductwork.logger).to receive(:warn).and_call_original

      expect do
        described_class.report_heartbeat!
      end.to change(described_class, :count).by(1)

      expect(Ductwork.logger).to have_received(:warn).with(
        msg: "Process record missing, re-adopting (likely reaped after host suspend)",
        pid: ::Process.pid
      )

      record = described_class.current
      expect(record.pid).to eq(::Process.pid)
      expect(record.machine_identifier).to eq(Ductwork::MachineIdentifier.fetch)
      expect(record.last_heartbeat_at).to be_almost_now
    end
  end

  describe "#reap!" do
    subject(:process) do
      create(:process, :current, last_heartbeat_at: 2.minutes.ago)
    end

    it "releases associated incomplete branch advancements" do
      advancement = create(:advancement, process:)
      branch = advancement.transition.branch.tap do |b|
        b.update!(claimed_for_advancing_at: Time.current)
      end

      expect do
        process.reap!(:process_supervisor)
      end.to change { branch.reload.claimed_for_advancing_at }.to(nil)
    end

    it "re-enqueues claimed jobs with incomplete executions" do
      availability = create(:availability, process: process, completed_at: Time.current)
      execution = availability.execution

      process.reap!(:thread_supervisor)

      expect(execution.reload.completed_at).to be_present
      expect(execution.result.result_type).to eq("process_crashed")

      new_execution = execution.job.executions.where.not(id: execution.id).sole
      expect(new_execution.retry_count).to eq(execution.retry_count)
      expect(new_execution.availability).to be_present
      expect(new_execution.availability.completed_at).to be_nil
    end

    it "destroys itself" do
      expect do
        process.reap!(:thread_supervisor)
      end.to change(process, :persisted?).from(true).to(false)
    end

    it "logs" do
      allow(Ductwork.logger).to receive(:debug).and_call_original

      process.reap!(:process_supervisor)

      expect(Ductwork.logger).to have_received(:debug).with(
        msg: "Reaping orphaned process record #{process.id}",
        id: process.id,
        role: :process_supervisor
      )
      expect(Ductwork.logger).to have_received(:debug).with(
        msg: "Reaped orphaned process record #{process.id}",
        id: process.id,
        role: :process_supervisor
      )
    end
  end
end
