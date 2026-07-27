# frozen_string_literal: true

RSpec.describe Ductwork::PollingInterval do
  describe ".jittered" do
    it "stays within the jitter ratio of the configured timeout" do
      durations = Array.new(500) { described_class.jittered(1) }

      expect(durations).to all(be_between(0.75, 1.25))
    end

    it "scales the spread with the timeout" do
      durations = Array.new(500) { described_class.jittered(8) }

      expect(durations).to all(be_between(6.0, 10.0))
      expect(durations.max).to be > 8
      expect(durations.min).to be < 8
    end

    it "centers on the configured timeout" do
      average = Array.new(2_000) { described_class.jittered(1) }.sum / 2_000

      expect(average).to be_within(0.03).of(1)
    end

    it "spreads durations across the band so pollers do not stay in lockstep" do
      durations = Array.new(50) { described_class.jittered(1) }

      expect(durations.max - durations.min).to be > 0.25
    end

    it "handles a zero timeout" do
      expect(described_class.jittered(0)).to eq(0)
    end
  end
end
