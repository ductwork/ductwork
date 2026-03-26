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
    let(:be_almost_now) { be_within(1.second).of(Time.current) }

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

      current_process = described_class.current

      expect(current_process).to eq(process)
    end

    it "raises if no record exists" do
      expect do
        described_class.current
      end.to raise_error(described_class::NotFoundError, "Process #{pid} not found")
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

    it "raises if the record does not exist" do
      expect do
        described_class.report_heartbeat!
      end.to raise_error(described_class::NotFoundError, "Process #{pid} not found")
    end
  end
end
