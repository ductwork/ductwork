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

    it "sets the pipeline id instance variable" do
      pipeline_id = 1

      step = described_class.build_for_execution(pipeline_id)

      expect(step.instance_variable_get(:@pipeline_id)).to eq(pipeline_id)
    end
  end

  describe "#pipeline_id" do
    let(:pipeline_id) { SecureRandom.uuid_v7 }

    it "returns the value of the instance variable" do
      step = described_class.new
      step.instance_variable_set(:@pipeline_id, pipeline_id)

      expect(step.pipeline_id).to eq(pipeline_id)
    end

    it "calls super otherwise" do
      step = described_class.new(pipeline_id:)

      expect(step.pipeline_id).to eq(pipeline_id)
    end
  end

  describe "#context" do
    let(:pipeline) { build_stubbed(:pipeline) }

    it "returns the context object" do
      context = described_class.new(pipeline:).context

      expect(context).to be_a(Ductwork::Context)
    end
  end
end
