# frozen_string_literal: true

RSpec.describe Ductwork::DSL::DefinitionBuilder, "#combine" do
  let(:builder) { described_class.new }

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
    allow(SecureRandom).to receive(:hex).and_return("0", "1", "2", "3")

    definition = builder
      .start(MyFirstStep)
      .divide(to: [MySecondStep, MyThirdStep])
      .combine(into: MyFourthStep)
      .complete

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2 MyFourthStep.3]
    )
    expect(definition[:edges].length).to eq(4)
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: %w[MySecondStep.1 MyThirdStep.2], type: :divide, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq(
      { to: %w[MyFourthStep.3], type: :combine, klass: "MySecondStep" }
    )
    expect(definition[:edges]["MyThirdStep.2"]).to eq(
      { to: %w[MyFourthStep.3], type: :combine, klass: "MyThirdStep" }
    )
    expect(definition[:edges]["MyFourthStep.3"]).to eq({ klass: "MyFourthStep" })
  end

  it "merges multiple branches together into a new step" do
    allow(SecureRandom).to receive(:hex).and_return("0", "1", "2", "3", "4")

    definition = builder
      .start(MyFirstStep)
      .divide(to: [MySecondStep, MyThirdStep, MyFourthStep])
      .combine(into: MyFifthStep)
      .complete

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2 MyFourthStep.3 MyFifthStep.4]
    )
    expect(definition[:edges].length).to eq(5)
    expect(definition[:edges]["MySecondStep.1"]).to eq(
      { to: %w[MyFifthStep.4], type: :combine, klass: "MySecondStep" }
    )
    expect(definition[:edges]["MyThirdStep.2"]).to eq(
      { to: %w[MyFifthStep.4], type: :combine, klass: "MyThirdStep" }
    )
    expect(definition[:edges]["MyFourthStep.3"]).to eq(
      { to: %w[MyFifthStep.4], type: :combine, klass: "MyFourthStep" }
    )
  end

  it "merges the branches together into a new step when given a block" do
    allow(SecureRandom).to receive(:hex).and_return("0", "1", "2", "3", "4")

    definition = builder.start(MyFirstStep).divide(to: [MySecondStep, MyThirdStep, MyFourthStep]) do |b1, b2, b3|
      b1.combine(b2, b3, into: MyFifthStep)
    end.complete

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2 MyFourthStep.3 MyFifthStep.4]
    )
    expect(definition[:edges].length).to eq(5)
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      {
        to: %w[MySecondStep.1 MyThirdStep.2 MyFourthStep.3],
        type: :divide,
        klass: "MyFirstStep",
      }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq(
      { to: %w[MyFifthStep.4], type: :combine, klass: "MySecondStep" }
    )
    expect(definition[:edges]["MyThirdStep.2"]).to eq(
      { to: %w[MyFifthStep.4], type: :combine, klass: "MyThirdStep" }
    )
    expect(definition[:edges]["MyFourthStep.3"]).to eq(
      { to: %w[MyFifthStep.4], type: :combine, klass: "MyFourthStep" }
    )
    expect(definition[:edges]["MyFifthStep.4"]).to eq({ klass: "MyFifthStep" })
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
