# frozen_string_literal: true

RSpec.describe Ductwork::DefinitionBuilder do
  let(:builder) { described_class.new }

  describe "#start" do
    it "returns the builder instance" do
      returned_builder = builder.start(MyFirstStep)

      expect(returned_builder).to eq(builder)
    end

    it "adds the initial branch and step to the definition" do
      definition = builder.start(MyFirstStep).complete

      step = definition.branch.steps.sole
      expect(step.klass).to eq(MyFirstStep)
      expect(step.type).to eq(:start)
    end

    it "raises if called more than once" do
      expect do
        builder.start(spy).start(spy)
      end.to raise_error(
        described_class::StartError,
        "Can only start pipeline definition once"
      )
    end
  end

  describe "#chain" do
    it "returns the builder instance" do
      returned_builder = builder.start(MyFirstStep).chain(MySecondStep)

      expect(returned_builder).to eq(builder)
    end

    it "adds a new step to the current branch of the definition" do
      definition = builder.start(MyFirstStep).chain(MySecondStep).complete

      first_step, last_step = definition.branch.steps
      expect(definition.branch.steps.length).to eq(2)
      expect(first_step.klass).to eq(MyFirstStep)
      expect(first_step.type).to eq(:start)
      expect(last_step.klass).to eq(MySecondStep)
      expect(last_step.type).to eq(:chain)
    end

    it "raises if pipeline has not been started" do
      expect do
        builder.chain(spy)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline definition before chaining"
      )
    end
  end

  describe "#divide" do
    it "returns the builder instance" do
      returned_builder = builder.start(MyFirstStep).divide(to: [MySecondStep, MyThirdStep])

      expect(returned_builder).to eq(builder)
    end

    it "returns the builder instance when given a block" do
      returned_builder = builder.start(MyFirstStep).divide(to: [MySecondStep, MyThirdStep]) do
        puts
      end

      expect(returned_builder).to eq(builder)
    end

    it "adds new branches and steps to the definition" do
      definition = builder.start(MyFirstStep).divide(to: [MySecondStep, MyThirdStep]).complete

      first_step = definition.branch.steps.sole
      second_step, third_step = definition.branch.children.map { |b| b.steps.sole }
      expect(first_step.klass).to eq(MyFirstStep)
      expect(second_step.klass).to eq(MySecondStep)
      expect(third_step.klass).to eq(MyThirdStep)
    end

    it "yields the new branches if a block is given" do
      expect do |block|
        builder.start(MyFirstStep).divide(to: [MySecondStep, MyThirdStep], &block)
      end.to yield_control
    end

    it "raises if pipeline has not been started" do
      expect do
        builder.divide(to: [spy, spy])
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline definition before dividing"
      )
    end
  end

  describe "#combine" do
    it "returns the builder instance with method chaining" do
      returned_builder = builder
                         .start(MyFirstStep)
                         .divide(to: [MySecondStep, MyThirdStep])
                         .combine(into: MyFourthStep)

      expect(returned_builder).to eq(builder)
    end

    it "returns the builder instance when given a block" do
      returned_builder = builder.start(MyFirstStep).divide(to: [MySecondStep, MyThirdStep]) do |b1, b2|
        b1.combine(b2, into: MyFourthStep)
      end

      expect(returned_builder).to eq(builder)
    end

    it "merges the branches together into a new step with method chaining" do
      definition = builder
                   .start(MyFirstStep)
                   .divide(to: [MySecondStep, MyThirdStep])
                   .combine(into: MyFourthStep)
                   .complete

      first_step = definition.branch.steps.sole
      second_step, third_step = definition.branch.children.map { |b| b.steps.sole }
      fourth_step = definition.branch.children.first.children.sole.steps.sole
      expect(first_step.klass).to eq(MyFirstStep)
      expect(second_step.klass).to eq(MySecondStep)
      expect(third_step.klass).to eq(MyThirdStep)
      expect(fourth_step.klass).to eq(MyFourthStep)
    end

    it "merges multiple branches together into a new step" do
      definition = builder
                   .start(MyFirstStep)
                   .divide(to: [MySecondStep, MyThirdStep, MyFourthStep])
                   .combine(into: MyFifthStep)
                   .complete

      combined_branch = definition.branch.children.sample.children.sole
      expect(definition.branch.children.length).to eq(3)
      expect(combined_branch.parents.length).to eq(3)
      expect(combined_branch.steps.sole.klass).to eq(MyFifthStep)
    end

    it "merges the branches together into a new step when given a block" do
      definition = builder.start(MyFirstStep).divide(to: [MySecondStep, MyThirdStep]) do |b1, b2|
        b1.combine(b2, into: MyFourthStep)
      end.complete

      first_step = definition.branch.steps.sole
      second_step, third_step = definition.branch.children.map { |b| b.steps.sole }
      fourth_step = definition.branch.children.first.children.sole.steps.sole
      expect(first_step.klass).to eq(MyFirstStep)
      expect(second_step.klass).to eq(MySecondStep)
      expect(third_step.klass).to eq(MyThirdStep)
      expect(fourth_step.klass).to eq(MyFourthStep)
    end

    it "raises if pipeline has not been started" do
      expect do
        builder.combine(into: spy)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline definition before combining"
      )
    end

    it "raises if the pipeline is not divided" do
      expect do
        builder.start(spy).combine(into: spy)
      end.to raise_error(
        described_class::CombineError,
        "Must divide pipeline definition before combining steps"
      )
    end
  end

  describe "#expand" do
    it "returns the builder instance" do
      returned_builder = builder.start(MyFirstStep).expand(to: MySecondStep)

      expect(returned_builder).to eq(builder)
    end

    it "adds a placeholder step to the definition" do
      definition = builder.start(MyFirstStep).expand(to: MySecondStep).complete

      step = definition.branch.steps.last
      expect(definition.branch.steps.length).to eq(2)
      expect(step.klass).to eq(MySecondStep)
      expect(step.type).to eq(:expand)
    end

    it "raises if pipeline has not been started" do
      expect do
        builder.expand(to: spy)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline definition before expanding chain"
      )
    end
  end

  describe "#collapse" do
    it "returns the builder instance" do
      returned_builder = builder
                         .start(MyFirstStep)
                         .expand(to: MySecondStep)
                         .collapse(into: MyThirdStep)

      expect(returned_builder).to eq(builder)
    end

    it "adds a step to the definition" do
      definition = builder
                   .start(MyFirstStep)
                   .expand(to: MySecondStep)
                   .collapse(into: MyThirdStep)
                   .complete

      first_step, second_step, third_step = definition.branch.steps
      expect(definition.branch.steps.length).to eq(3)
      expect(first_step.klass).to eq(MyFirstStep)
      expect(second_step.klass).to eq(MySecondStep)
      expect(third_step.klass).to eq(MyThirdStep)
      expect(third_step.type).to eq(:collapse)
    end

    it "raises if pipeline has not been started" do
      expect do
        builder.collapse(into: spy)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline definition before collapsing steps"
      )
    end

    it "raises if chain is not expanded" do
      expect do
        builder.start(spy).collapse(into: spy)
      end.to raise_error(
        described_class::CollapseError,
        "Must expand pipeline definition before collapsing steps"
      )
    end
  end

  describe "#complete" do
    it "raises if pipeline has not been started" do
      expect do
        builder.complete
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline definition before completing"
      )
    end
  end
end
