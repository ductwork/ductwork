# frozen_string_literal: true

RSpec.describe Ductwork::DefinitionBuilder do
  let(:builder) { described_class.new }

  describe "#start" do
    it "returns the builder instance" do
      returned_builder = builder.start(MyFirstJob)

      expect(returned_builder).to eq(builder)
    end

    it "adds the initial branch and step to the definition" do
      definition = builder.start(MyFirstJob).complete

      step = definition.branch.steps.sole
      expect(step.klass).to eq(MyFirstJob)
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
      returned_builder = builder.start(MyFirstJob).chain(MySecondJob)

      expect(returned_builder).to eq(builder)
    end

    it "adds a new step to the current branch of the definition" do
      definition = builder.start(MyFirstJob).chain(MySecondJob).complete

      first_step, last_step = definition.branch.steps
      expect(definition.branch.steps.length).to eq(2)
      expect(first_step.klass).to eq(MyFirstJob)
      expect(first_step.type).to eq(:start)
      expect(last_step.klass).to eq(MySecondJob)
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
      returned_builder = builder.start(MyFirstJob).divide(to: [MySecondJob, MyThirdJob])

      expect(returned_builder).to eq(builder)
    end

    it "adds new branches and steps to the definition" do
      definition = builder.start(MyFirstJob).divide(to: [MySecondJob, MyThirdJob]).complete

      first_step = definition.branch.steps.sole
      second_step, third_step = definition.branch.children.map { |b| b.steps.sole }
      expect(first_step.klass).to eq(MyFirstJob)
      expect(second_step.klass).to eq(MySecondJob)
      expect(third_step.klass).to eq(MyThirdJob)
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
                         .start(MyFirstJob)
                         .divide(to: [MySecondJob, MyThirdJob])
                         .combine(into: MyFourthJob)

      expect(returned_builder).to eq(builder)
    end

    it "returns the builder instance when given a block" do
      returned_builder = builder.start(MyFirstJob).divide(to: [MySecondJob, MyThirdJob]) do |b1, b2|
        b1.combine(b2, into: MyFourthJob)
      end

      expect(returned_builder).to eq(builder)
    end

    it "merges the branches together into a new step with method chaining" do
      definition = builder
                   .start(MyFirstJob)
                   .divide(to: [MySecondJob, MyThirdJob])
                   .combine(into: MyFourthJob)
                   .complete

      first_step = definition.branch.steps.sole
      second_step, third_step = definition.branch.children.map { |b| b.steps.sole }
      fourth_step = definition.branch.children.first.children.sole.steps.sole
      expect(first_step.klass).to eq(MyFirstJob)
      expect(second_step.klass).to eq(MySecondJob)
      expect(third_step.klass).to eq(MyThirdJob)
      expect(fourth_step.klass).to eq(MyFourthJob)
    end

    it "merges the branches together into a new step when given a block" do
      definition = builder.start(MyFirstJob).divide(to: [MySecondJob, MyThirdJob]) do |b1, b2|
        b1.combine(b2, into: MyFourthJob)
      end.complete

      first_step = definition.branch.steps.sole
      second_step, third_step = definition.branch.children.map { |b| b.steps.sole }
      fourth_step = definition.branch.children.first.children.sole.steps.sole
      expect(first_step.klass).to eq(MyFirstJob)
      expect(second_step.klass).to eq(MySecondJob)
      expect(third_step.klass).to eq(MyThirdJob)
      expect(fourth_step.klass).to eq(MyFourthJob)
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
      returned_builder = builder.start(MyFirstJob).expand(to: MySecondJob)

      expect(returned_builder).to eq(builder)
    end

    it "adds a placeholder step to the definition" do
      definition = builder.start(MyFirstJob).expand(to: MySecondJob).complete

      step = definition.branch.steps.last
      expect(definition.branch.steps.length).to eq(2)
      expect(step.klass).to eq(MySecondJob)
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
                         .start(MyFirstJob)
                         .expand(to: MySecondJob)
                         .collapse(into: MyThirdJob)

      expect(returned_builder).to eq(builder)
    end

    it "adds a step to the definition" do
      definition = builder
                   .start(MyFirstJob)
                   .expand(to: MySecondJob)
                   .collapse(into: MyThirdJob)
                   .complete

      first_step, second_step, third_step = definition.branch.steps
      expect(definition.branch.steps.length).to eq(3)
      expect(first_step.klass).to eq(MyFirstJob)
      expect(second_step.klass).to eq(MySecondJob)
      expect(third_step.klass).to eq(MyThirdJob)
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
