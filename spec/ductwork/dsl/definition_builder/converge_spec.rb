# frozen_string_literal: true

RSpec.describe Ductwork::DSL::DefinitionBuilder, "#converge" do
  let(:builder) { described_class.new }

  it "returns the builder instance with method chaining" do
    returned_builder = builder
      .start(MyFirstStep)
      .divert(to: { bar: MySecondStep, otherwise: MyThirdStep })
      .converge(into: MyFourthStep)

    expect(returned_builder).to eq(builder)
  end

  it "returns the builder instance when given a block" do
    returned_builder = builder.start(MyFirstStep).divert(to: { bar: MySecondStep, otherwise: MyThirdStep }) do |b1, b2|
      b1.converge(b2, into: MyFourthStep)
    end

    expect(returned_builder).to eq(builder)
  end

  it "converges the branches together into a new step with method chaining" do
    allow(SecureRandom).to receive(:hex).and_return("0", "1", "2", "3")

    definition = builder
      .start(MyFirstStep)
      .divert(to: { bar: MySecondStep, otherwise: MyThirdStep })
      .converge(into: MyFourthStep)
      .complete

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2 MyFourthStep.3]
    )
    expect(definition[:edges].length).to eq(4)
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: { "bar" => "MySecondStep.1", "otherwise" => "MyThirdStep.2" }, type: :divert, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq(
      { to: %w[MyFourthStep.3], type: :converge, klass: "MySecondStep" }
    )
    expect(definition[:edges]["MyThirdStep.2"]).to eq(
      { to: %w[MyFourthStep.3], type: :converge, klass: "MyThirdStep" }
    )
    expect(definition[:edges]["MyFourthStep.3"]).to eq({ klass: "MyFourthStep" })
  end

  it "converges the branches together into a new step when given a block" do
    allow(SecureRandom).to receive(:hex).and_return("0", "1", "2", "3")

    definition = builder.start(MyFirstStep).divert(to: { bar: MySecondStep, otherwise: MyThirdStep }) do |b1, b2|
      b1.converge(b2, into: MyFourthStep)
    end.complete

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2 MyFourthStep.3]
    )
    expect(definition[:edges].length).to eq(4)
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      {
        to: { "bar" => "MySecondStep.1", "otherwise" => "MyThirdStep.2" },
        type: :divert,
        klass: "MyFirstStep",
      }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq(
      { to: %w[MyFourthStep.3], type: :converge, klass: "MySecondStep" }
    )
    expect(definition[:edges]["MyThirdStep.2"]).to eq(
      { to: %w[MyFourthStep.3], type: :converge, klass: "MyThirdStep" }
    )
    expect(definition[:edges]["MyFourthStep.3"]).to eq({ klass: "MyFourthStep" })
  end

  it "raises if a value is not a valid step class" do
    expect do
      builder
        .start(MyFirstStep)
        .divert(to: { bar: MySecondStep, otherwise: MyThirdStep })
        .converge(into: "MyFourthStep")
    end.to raise_error(
      ArgumentError,
      "Argument must be a valid step class"
    )
  end

  it "raises if pipeline has not been started" do
    expect do
      builder.converge(into: MyFirstStep)
    end.to raise_error(
      described_class::StartError,
      "Must start pipeline definition before converging steps"
    )
  end

  it "raises if the pipeline is not diverted" do
    expect do
      builder.start(MyFirstStep).converge(into: MySecondStep)
    end.to raise_error(
      described_class::ConvergeError,
      "Must divert pipeline definition before converging steps"
    )
  end

  it "raises if the pipeline is not diverted and steps are chained" do
    expect do
      builder
        .start(MyFirstStep)
        .chain(MySecondStep)
        .converge(into: MyThirdStep)
    end.to raise_error(
      described_class::ConvergeError,
      "Must divert pipeline definition before converging steps"
    )
  end

  it "raises an error when the pipeline is most recently divided" do
    expect do
      builder
        .start(MyFirstStep)
        .divert(to: { bar: MyThirdStep, otherwise: MyFourthStep })
        .divide(to: [MySecondStep, MyFifthStep])
        .converge(into: MyFirstStep)
    end.to raise_error(
      described_class::ConvergeError,
      "Ambiguous converge on most recently divided/expanded definition"
    )
  end
end
