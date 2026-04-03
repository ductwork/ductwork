# frozen_string_literal: true

RSpec.describe Ductwork::Step do
  describe "validations" do
    let(:node) { "MyStep.0" }
    let(:klass) { "MyStep" }
    let(:status) { "in_progress" }
    let(:to_transition) { :expand }

    it "is invalid if the `node` is not present" do
      step = described_class.new(klass:, status:, to_transition:)

      expect(step).not_to be_valid
      expect(step.errors.full_messages).to eq(["Node can't be blank"])
    end

    it "is invalid if the `klass` is not present" do
      step = described_class.new(node:, status:, to_transition:)

      expect(step).not_to be_valid
      expect(step.errors.full_messages).to eq(["Klass can't be blank"])
    end

    it "is invalid if the `status` is not present" do
      step = described_class.new(node:, klass:, to_transition:)

      expect(step).not_to be_valid
      expect(step.errors.full_messages).to eq(["Status can't be blank"])
    end

    it "is invalid if the `to_transition` is not present" do
      step = described_class.new(node:, klass:, status:)

      expect(step).not_to be_valid
      expect(step.errors.full_messages).to eq(["To transition can't be blank"])
    end

    it "is valid otherwise" do
      step = described_class.new(node:, klass:, status:, to_transition:)

      expect(step).to be_valid
    end
  end

  describe ".build_for_execution" do
    it "returns an instantiated instance of step" do
      step = described_class.build_for_execution(spy)

      expect(step).to be_a(described_class)
    end

    it "sets the run id instance variable" do
      run_id = 1

      step = described_class.build_for_execution(run_id)

      expect(step.instance_variable_get(:@run_id)).to eq(run_id)
    end
  end

  describe "#run_id" do
    let(:run_id) { SecureRandom.uuid_v7 }

    it "returns the value of the instance variable" do
      step = described_class.new
      step.instance_variable_set(:@run_id, run_id)

      expect(step.run_id).to eq(run_id)
    end

    it "calls super otherwise" do
      step = described_class.new(run_id:)

      expect(step.run_id).to eq(run_id)
    end
  end

  describe "#context" do
    let(:run) { build_stubbed(:run) }

    it "returns the context object" do
      ctx = described_class.new(run:).context

      expect(ctx).to be_a(Ductwork::Context)
    end
  end
end
