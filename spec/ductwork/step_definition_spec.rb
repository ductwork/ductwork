# frozen_string_literal: true

RSpec.describe Ductwork::StepDefinition do
  let(:klass) { Class.new }
  let(:type) { :chain }

  describe "#klass" do
    it "returns the value" do
      step = described_class.new(klass: klass, type: type)

      expect(step.klass).to eq(klass)
    end
  end

  describe "#type" do
    it "returns the value" do
      step = described_class.new(klass: klass, type: type)

      expect(step.type).to eq(type)
    end
  end

  describe "#first?" do
    it "returns true when the step definition is first" do
      step = described_class.new(klass: klass, type: :start)

      expect(step).to be_first
    end

    it "returns false when the step definition is not first" do
      step = described_class.new(klass: klass, type: :chain)

      expect(step).not_to be_first
    end
  end
end
