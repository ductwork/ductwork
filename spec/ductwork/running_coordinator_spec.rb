# frozen_string_literal: true

RSpec.describe Ductwork::RunningCoordinator do
  subject(:coordinator) { described_class.new }

  describe "#running?" do
    it "returns true when running" do
      expect(coordinator).to be_running
    end

    it "returns false after shutdown" do
      coordinator.shutdown!

      expect(coordinator).not_to be_running
    end
  end

  describe "#shutdown!" do
    it "sets running to false" do
      expect do
        coordinator.shutdown!
      end.to change(coordinator, :running?).from(true).to(false)
    end
  end
end
