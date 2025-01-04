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
end
