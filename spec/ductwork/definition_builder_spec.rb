# frozen_string_literal: true

RSpec.describe Ductwork::DefinitionBuilder do
  let(:builder) { described_class.new }

  describe "#start" do
    it "returns the builder instance" do
      returned_builder = builder.start(MyFirstJob)

      expect(returned_builder).to eq(builder)
    end

    it "adds the initial step to the definition" do
      definition = builder.start(MyFirstJob).complete

      stage = definition.stages.sole
      expect(definition.stages.length).to eq(1)
      expect(stage.nodes.sole.klass).to eq(MyFirstJob)
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
    it "returns the builder instance" do
      returned_builder = builder.start(MyFirstJob).chain(MySecondJob)

      expect(returned_builder).to eq(builder)
    end

    it "adds a new stage a step to the definition" do
      definition = builder.start(MyFirstJob).chain(MySecondJob).complete

      first_node = definition.stages.first.nodes.sole
      last_node = definition.stages.last.nodes.sole
      expect(definition.stages.length).to eq(2)
      expect(first_node.edges.length).to eq(1)
      expect(first_node.edges.sole.type).to eq(:chain)
      expect(last_node.klass).to eq(MySecondJob)
      expect(last_node.edges).to be_empty
    end

    it "raises if pipeline has not been started" do
      expect do
        builder.chain(spy)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline before chaining"
      )
    end
  end

  describe "#divide" do
    it "returns the builder instance" do
      returned_builder = builder.start(MyFirstJob).divide(to: [MySecondJob, MyThirdJob])

      expect(returned_builder).to eq(builder)
    end

    it "adds a new stage and steps to the definition" do
      definition = builder.start(MyFirstJob).divide(to: [MySecondJob, MyThirdJob]).complete

      first_node = definition.stages.first.nodes.sole
      second_node, third_node = definition.stages.last.nodes

      expect(definition.stages.length).to eq(2)
      expect(first_node.edges.length).to eq(2)
      expect(first_node.edges.map(&:type)).to eq(%i[divide divide])
      expect(first_node.edges.first.ending_node).to eq(second_node)
      expect(first_node.edges.last.ending_node).to eq(third_node)
      expect(second_node.klass).to eq(MySecondJob)
      expect(second_node.edges).to be_empty
      expect(third_node.klass).to eq(MyThirdJob)
      expect(third_node.edges).to be_empty
    end

    it "raises if pipeline has not been started" do
      expect do
        builder.divide(to: [spy, spy])
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline before dividing"
      )
    end
  end

  describe "#combine" do
    it "returns the builder instance" do
      pending "must implement the functionality"
      returned_builder = nil

      builder.start(MyFirstJob).divide(to: [MySecondJob, MyThirdJob]) do |b1, b2|
        returned_builder = b1.combine(b2, into: MyFourthJob)
      end

      expect(returned_builder).to eq(builder)
    end

    it "raises if pipeline has not been started" do
      expect do
        builder.combine(into: spy)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline before combining"
      )
    end

    it "raises if the pipeline is not divided" do
      expect do
        builder.start(spy).combine(into: spy)
      end.to raise_error(
        described_class::CombineError,
        "Must divide pipeline before combining steps"
      )
    end
  end

  describe "#expand" do
    it "adds a new stage and expanded steps to the definition" do
      pending "must implement the functionality"
      definition = builder.start(MyFirstJob).expand(to: MySecondJob).complete

      stage = definition.stages.last
      expect(definition.stages.length).to eq(2)
      expect(stage.nodes.sole.klass).to eq(MySecondJob)
    end

    it "raises if pipeline has not been started" do
      expect do
        builder.expand(to: spy)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline before expanding chain"
      )
    end
  end

  describe "#collapse" do
    it "raises if pipeline has not been started" do
      expect do
        builder.collapse(into: spy)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline before collapsing steps"
      )
    end

    it "raises if chain is not expanded" do
      expect do
        builder.start(spy).collapse(into: spy)
      end.to raise_error(
        described_class::CollapseError,
        "Must expand pipeline before collapsing steps"
      )
    end
  end

  describe "#complete" do
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
