# frozen_string_literal: true

RSpec.describe Ductwork::Step do
  describe "validations" do
    let(:pipeline_id) { 1 }
    let(:step_type) { :expand }
    let(:klass) { "MyJob" }

    it "is invalid if the `step_type` is not present" do
      step = described_class.new(klass:, pipeline_id:)

      expect(step).not_to be_valid
      expect(step.errors.full_messages).to eq(["Step type can't be blank"])
    end

    it "is invalid if the `klass` is not present" do
      step = described_class.new(step_type:, pipeline_id:)

      expect(step).not_to be_valid
      expect(step.errors.full_messages).to eq(["Klass can't be blank"])
    end

    it "is invalid if the pipeline ID is not present" do
      step = described_class.new(step_type:, klass:)

      expect(step).not_to be_valid
      expect(step.errors.full_messages).to eq(["Pipeline can't be blank"])
    end

    it "is valid otherwise" do
      step = described_class.new(step_type:, klass:, pipeline_id:)

      expect(step).to be_valid
    end
  end
end
