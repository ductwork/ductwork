# frozen_string_literal: true

RSpec.describe Ductwork::MachineIdentifier do
  describe ".fetch" do
    it "returns the machine id from the file" do
      machine_id = File.read("/etc/machine-id").strip

      expect(described_class.fetch).to eq(machine_id)
    end

    it "uses hostname if machine id is not present" do
      hostname = Socket.gethostname
      allow(File).to receive(:read).and_return(" ")

      expect(described_class.fetch).to eq(hostname)
    end

    it "falls back to hostname" do
      hostname = Socket.gethostname
      allow(File).to receive(:read).and_raise(Errno::ENOENT, "File not found")

      expect(described_class.fetch).to eq(hostname)
    end
  end
end
