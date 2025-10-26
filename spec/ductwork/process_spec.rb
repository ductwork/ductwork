# frozen_string_literal: true

RSpec.describe Ductwork::Process do
  let(:pid) { ::Process.pid }
  let(:machine_identifier) do
    File.read("/etc/machine-id").strip
  rescue Errno::ENOENT
    Socket.gethostname
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
      described_class.create!(pid:, machine_identifier: "foo", last_heartbeat_at:)

      process = described_class.new(pid:, machine_identifier:, last_heartbeat_at:)

      expect(process).to be_valid
    end
  end

  describe ".report_heartbeat!" do
    it "updates the heartbeat timestamp" do
      process = described_class.create!(
        pid:,
        machine_identifier:,
        last_heartbeat_at: 1.day.ago
      )

      expect do
        described_class.report_heartbeat!
      end.to change { process.reload.last_heartbeat_at }.to(
        be_within(1.second).of(Time.current)
      )
    end

    it "queries the record by pid and machine identifier" do
      described_class.create!(
        pid:,
        machine_identifier: "foobar",
        last_heartbeat_at: 1.day.ago
      )
      process = described_class.create!(
        pid:,
        machine_identifier:,
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
