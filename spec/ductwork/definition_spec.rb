# frozen_string_literal: true

RSpec.describe Ductwork::Definition do
  describe "#steps" do
    it "returns the collection of steps" do
      steps = described_class.new.steps

      expect(steps).to be_empty
    end
  end
end
