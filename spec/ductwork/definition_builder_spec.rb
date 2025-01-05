# frozen_string_literal: true

RSpec.describe Ductwork::DefinitionBuilder do
  describe "#start" do
    let(:builder) { described_class.new }

    it "adds the initial step to the definition" do
      klass = Class.new do
        def self.name
          "MyJob"
        end
      end

      definition = builder.start(klass).complete

      step = definition.steps.first
      expect(definition.steps.length).to eq(1)
      expect(step.klass).to eq("MyJob")
      expect(step.type).to eq(:start)
    end

    it "raises if called more than once" do
      expect do
        builder.start(spy).start(spy)
      end.to raise_error(
        described_class::StartError,
        "Can only start pipeline once"
      )
    end
  end

  describe "#chain" do
    let(:builder) { described_class.new }

    it "raises if pipeline has not been started" do
      expect do
        builder.chain(spy)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline before chaining"
      )
    end

    it "adds a step to the definition" do
      klass = Class.new do
        def self.name
          "MyJob"
        end
      end

      definition = builder.start(klass).chain(klass).complete

      step = definition.steps.last
      expect(definition.steps.length).to eq(2)
      expect(step.klass).to eq("MyJob")
      expect(step.type).to eq(:chain)
    end
  end

  describe "#expand_chain" do
    let(:builder) { described_class.new }

    it "raises if pipeline has not been started" do
      expect do
        builder.expand_chain(spy)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline before expanding chain"
      )
    end

    it "adds a step to the definition" do
      klass = Class.new do
        def self.name
          "MyJob"
        end
      end

      definition = builder.start(klass).expand_chain(klass).complete

      step = definition.steps.last
      expect(definition.steps.length).to eq(2)
      expect(step.klass).to eq("MyJob")
      expect(step.type).to eq(:expand)
    end
  end

  describe "#collapse_chain" do
    let(:builder) { described_class.new }

    it "raises if pipeline has not been started" do
      expect do
        builder.collapse_chain(spy)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline before collapsing chain"
      )
    end

    it "raises if chain is not expanded" do
      expect do
        builder.start(spy).collapse_chain(spy)
      end.to raise_error(
        described_class::CollapseError,
        "Must expand pipeline before collapsing chain"
      )
    end
  end

  describe "#complete" do
    let(:builder) { described_class.new }

    it "raises if pipeline has not been started" do
      expect do
        builder.complete
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline before completing definition"
      )
    end
  end
end
