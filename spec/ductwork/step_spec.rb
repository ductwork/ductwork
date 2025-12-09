# frozen_string_literal: true

RSpec.describe Ductwork::Step do
  describe "validations" do
    let(:to_transition) { :expand }
    let(:klass) { "MyJob" }
    let(:status) { "in_progress" }

    it "is invalid if the `to_transition` is not present" do
      step = described_class.new(klass:, status:)

      expect(step).not_to be_valid
      expect(step.errors.full_messages).to eq(["To transition can't be blank"])
    end

    it "is invalid if the `klass` is not present" do
      step = described_class.new(to_transition:, status:)

      expect(step).not_to be_valid
      expect(step.errors.full_messages).to eq(["Klass can't be blank"])
    end

    it "is invalid if the status is not present" do
      step = described_class.new(to_transition:, klass:)

      expect(step).not_to be_valid
      expect(step.errors.full_messages).to eq(["Status can't be blank"])
    end

    it "is valid otherwise" do
      step = described_class.new(to_transition:, klass:, status:)

      expect(step).to be_valid
    end
  end
end
