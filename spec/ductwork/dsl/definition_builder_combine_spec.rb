# frozen_string_literal: true

RSpec.describe Ductwork::DSL::DefinitionBuilder do
  let(:builder) { described_class.new }

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
          { to: %w[MySecondStep MyThirdStep], type: :divide },
        ]
      )
      expect(definition[:edges]["MySecondStep"]).to eq(
        [
          { to: %w[MyFourthStep], type: :combine },
        ]
      )
      expect(definition[:edges]["MyThirdStep"]).to eq(
        [
          { to: %w[MyFourthStep], type: :combine },
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
          { to: %w[MyFifthStep], type: :combine },
        ]
      )
      expect(definition[:edges]["MyThirdStep"]).to eq(
        [
          { to: %w[MyFifthStep], type: :combine },
        ]
      )
      expect(definition[:edges]["MyFourthStep"]).to eq(
        [
          { to: %w[MyFifthStep], type: :combine },
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
          { to: %w[MySecondStep MyThirdStep MyFourthStep], type: :divide },
        ]
      )
      expect(definition[:edges]["MySecondStep"]).to eq(
        [
          { to: %w[MyFifthStep], type: :combine },
        ]
      )
      expect(definition[:edges]["MyThirdStep"]).to eq(
        [
          { to: %w[MyFifthStep], type: :combine },
        ]
      )
      expect(definition[:edges]["MyFourthStep"]).to eq(
        [
          { to: %w[MyFifthStep], type: :combine },
        ]
      )
      expect(definition[:edges]["MyFifthStep"]).to eq([])
    end

    it "raises if the argument is not a class" do
      expect do
        builder
          .start(MyFirstStep)
          .divide(to: [MySecondStep, MyThirdStep, MyFourthStep])
          .combine(into: "MyFifthStep")
      end.to raise_error(
        ArgumentError,
        "Argument must be a valid step class"
      )
    end

    it "raises if the argument does not have an 'execute' method" do
      expect do
        builder
          .start(MyFirstStep)
          .divide(to: [MySecondStep, MyThirdStep, MyFourthStep])
          .combine(into: Class.new)
      end.to raise_error(
        ArgumentError,
        "Argument must be a valid step class"
      )
    end

    it "raises if the argument does not have `execute` with arity zero" do
      klass = Class.new do
        def execute(_foobar); end
      end

      expect do
        builder
          .start(MyFirstStep)
          .divide(to: [MySecondStep, MyThirdStep, MyFourthStep])
          .combine(into: klass)
      end.to raise_error(
        ArgumentError,
        "Argument must be a valid step class"
      )
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

    it "raises an error when the pipeline is most recently expanded" do
      expect do
        builder
          .start(MyFirstStep)
          .divide(to: [MyThirdStep, MyFourthStep])
          .expand(to: MySecondStep)
          .combine(into: MyFifthStep)
      end.to raise_error(
        described_class::CombineError,
        "Ambiguous combine on most recently expanded definition"
      )
    end
  end
end
