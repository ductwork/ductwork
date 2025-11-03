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

      expect(definition[:nodes]).to eq(["MyFirstStep"])
      expect(definition[:edges].length).to eq(1)
      expect(definition[:edges]["MyFirstStep"]).to eq([])
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

      expect(definition[:nodes]).to eq(%w[MyFirstStep MySecondStep])
      expect(definition[:edges].length).to eq(2)
      expect(definition[:edges]["MyFirstStep"]).to eq(
        [
          {
            to: %w[MySecondStep],
            type: :chain,
          },
        ]
      )
      expect(definition[:edges]["MySecondStep"]).to eq([])
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
      definition = builder
                   .start(MyFirstStep)
                   .divide(to: [MySecondStep, MyThirdStep])
                   .complete

      expect(definition[:nodes]).to eq(%w[MyFirstStep MySecondStep MyThirdStep])
      expect(definition[:edges].length).to eq(3)
      expect(definition[:edges]["MyFirstStep"]).to eq(
        [
          {
            to: %w[MySecondStep MyThirdStep],
            type: :divide,
          },
        ]
      )
      expect(definition[:edges]["MySecondStep"]).to eq([])
      expect(definition[:edges]["MyThirdStep"]).to eq([])
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
        "Must start pipeline definition before dividing chain"
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

      expect(definition[:nodes]).to eq(
        %w[MyFirstStep MySecondStep MyThirdStep MyFourthStep]
      )
      expect(definition[:edges].length).to eq(4)
      expect(definition[:edges]["MyFirstStep"]).to eq(
        [
          {
            to: %w[MySecondStep MyThirdStep],
            type: :divide,
          },
        ]
      )
      expect(definition[:edges]["MySecondStep"]).to eq(
        [
          {
            to: %w[MyFourthStep],
            type: :combine,
          },
        ]
      )
      expect(definition[:edges]["MyThirdStep"]).to eq(
        [
          {
            to: %w[MyFourthStep],
            type: :combine,
          },
        ]
      )
      expect(definition[:edges]["MyFourthStep"]).to eq([])
    end

    it "merges multiple branches together into a new step" do
      definition = builder
                   .start(MyFirstStep)
                   .divide(to: [MySecondStep, MyThirdStep, MyFourthStep])
                   .combine(into: MyFifthStep)
                   .complete

      expect(definition[:edges].length).to eq(5)
      expect(definition[:edges]["MySecondStep"]).to eq(
        [
          {
            to: %w[MyFifthStep],
            type: :combine,
          },
        ]
      )
      expect(definition[:edges]["MyThirdStep"]).to eq(
        [
          {
            to: %w[MyFifthStep],
            type: :combine,
          },
        ]
      )
      expect(definition[:edges]["MyFourthStep"]).to eq(
        [
          {
            to: %w[MyFifthStep],
            type: :combine,
          },
        ]
      )
    end

    it "merges the branches together into a new step when given a block" do
      definition = builder.start(MyFirstStep).divide(to: [MySecondStep, MyThirdStep, MyFourthStep]) do |b1, b2, b3|
        b1.combine(b2, b3, into: MyFifthStep)
      end.complete

      expect(definition[:nodes]).to eq(
        %w[MyFirstStep MySecondStep MyThirdStep MyFourthStep MyFifthStep]
      )
      expect(definition[:edges].length).to eq(5)
      expect(definition[:edges]["MyFirstStep"]).to eq(
        [
          {
            to: %w[MySecondStep MyThirdStep MyFourthStep],
            type: :divide,
          },
        ]
      )
      expect(definition[:edges]["MySecondStep"]).to eq(
        [
          {
            to: %w[MyFifthStep],
            type: :combine,
          },
        ]
      )
      expect(definition[:edges]["MyThirdStep"]).to eq(
        [
          {
            to: %w[MyFifthStep],
            type: :combine,
          },
        ]
      )
      expect(definition[:edges]["MyFourthStep"]).to eq(
        [
          {
            to: %w[MyFifthStep],
            type: :combine,
          },
        ]
      )
      expect(definition[:edges]["MyFifthStep"]).to eq([])
    end

    it "raises if pipeline has not been started" do
      expect do
        builder.combine(into: MyFirstStep)
      end.to raise_error(
        described_class::StartError,
        "Must start pipeline definition before combining steps"
      )
    end

    it "raises if the pipeline is not divided" do
      expect do
        builder.start(MyFirstStep).combine(into: MySecondStep)
      end.to raise_error(
        described_class::CombineError,
        "Must divide pipeline definition before combining steps"
      )
    end

    it "raises if the pipeline is not divided and steps are chained" do
      expect do
        builder
          .start(MyFirstStep)
          .chain(MySecondStep)
          .combine(into: MyThirdStep)
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

    it "adds a step to the definition" do
      definition = builder.start(MyFirstStep).expand(to: MySecondStep).complete

      expect(definition[:nodes]).to eq(%w[MyFirstStep MySecondStep])
      expect(definition[:edges].length).to eq(2)
      expect(definition[:edges]["MyFirstStep"]).to eq(
        [
          {
            to: %w[MySecondStep],
            type: :expand,
          },
        ]
      )
      expect(definition[:edges]["MySecondStep"]).to eq([])
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

      expect(definition[:nodes]).to eq(%w[MyFirstStep MySecondStep MyThirdStep])
      expect(definition[:edges].length).to eq(3)
      expect(definition[:edges]["MyFirstStep"]).to eq(
        [
          {
            to: %w[MySecondStep],
            type: :expand,
          },
        ]
      )
      expect(definition[:edges]["MySecondStep"]).to eq(
        [
          {
            to: %w[MyThirdStep],
            type: :collapse,
          },
        ]
      )
      expect(definition[:edges]["MyThirdStep"]).to eq([])
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

    it "raises if chain is not expanded and steps are chained" do
      expect do
        builder
          .start(MyFirstStep)
          .chain(MySecondStep)
          .collapse(into: MyThirdStep)
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
