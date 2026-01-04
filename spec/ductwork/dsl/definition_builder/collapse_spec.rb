# frozen_string_literal: true

RSpec.describe Ductwork::DSL::DefinitionBuilder, "#collapse" do
  let(:builder) { described_class.new }

  it "returns the builder instance" do
    returned_builder = builder
      .start(MyFirstStep)
      .expand(to: MySecondStep)
      .collapse(into: MyThirdStep)

    expect(returned_builder).to eq(builder)
  end

  it "adds a step to the definition" do
    allow(SecureRandom).to receive(:hex).and_return("0", "1", "2")

    definition = builder
      .start(MyFirstStep)
      .expand(to: MySecondStep)
      .collapse(into: MyThirdStep)
      .complete

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2]
    )
    expect(definition[:edges].length).to eq(3)
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: %w[MySecondStep.1], type: :expand, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq(
      { to: %w[MyThirdStep.2], type: :collapse, klass: "MySecondStep" }
    )
    expect(definition[:edges]["MyThirdStep.2"]).to eq({ klass: "MyThirdStep" })
  end

  it "raises if the argument is not a class" do
    expect do
      builder
        .start(MyFirstStep)
        .expand(to: MySecondStep)
        .collapse(into: "MyThirdStep")
    end.to raise_error(
      ArgumentError,
      "Argument must be a valid step class"
    )
  end

  it "raises if the argument does not have an 'execute' method" do
    expect do
      builder
        .start(MyFirstStep)
        .expand(to: MySecondStep)
        .collapse(into: Class.new)
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
        .expand(to: MySecondStep)
        .collapse(into: klass)
    end.to raise_error(
      ArgumentError,
      "Argument must be a valid step class"
    )
  end

  it "raises if pipeline has not been started" do
    expect do
      builder.collapse(into: MyFirstStep)
    end.to raise_error(
      described_class::StartError,
      "Must start pipeline definition before collapsing steps"
    )
  end

  it "raises if chain is not expanded" do
    expect do
      builder.start(MyFirstStep).collapse(into: MyFirstStep)
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

  it "raises an error when the pipeline is most recently divided" do
    expect do
      builder
        .start(MyFirstStep)
        .expand(to: MySecondStep)
        .divide(to: [MyThirdStep, MyFourthStep])
        .collapse(into: MyFifthStep)
    end.to raise_error(
      described_class::CollapseError,
      "Ambiguous collapse on most recently divided definition"
    )
  end
end
