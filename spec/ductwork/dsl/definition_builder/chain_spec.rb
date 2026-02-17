# frozen_string_literal: true

RSpec.describe Ductwork::DSL::DefinitionBuilder, "#chain" do
  let(:builder) { described_class.new }

  it "returns the builder instance" do
    returned_builder = builder.start(MyFirstStep).chain(MySecondStep)

    expect(returned_builder).to eq(builder)
  end

  it "accepts an optional `to` keyword argument for better DSL readability" do
    returned_builder = builder.start(MyFirstStep).chain(to: MySecondStep)

    expect(returned_builder).to eq(builder)
  end

  it "adds a new step to the current branch of the definition" do
    allow(SecureRandom).to receive(:hex).and_return("0", "1")

    definition = builder.start(MyFirstStep).chain(MySecondStep).complete

    expect(definition[:nodes]).to eq(%w[MyFirstStep.0 MySecondStep.1])
    expect(definition[:edges].length).to eq(2)
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: %w[MySecondStep.1], type: :chain, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq({ klass: "MySecondStep" })
  end

  it "adds a new step for each active branch of the definition" do
    allow(SecureRandom).to receive(:hex).and_return("0", "1", "2", "3")

    definition = builder
      .start(MyFirstStep)
      .divide(to: [MySecondStep, MyThirdStep])
      .chain(MyFourthStep)
      .complete

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2 MyFourthStep.3]
    )
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: %w[MySecondStep.1 MyThirdStep.2], type: :divide, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq(
      { to: %w[MyFourthStep.3], type: :chain, klass: "MySecondStep" }
    )
    expect(definition[:edges]["MyThirdStep.2"]).to eq(
      { to: %w[MyFourthStep.3], type: :chain, klass: "MyThirdStep" }
    )
    expect(definition[:edges]["MyFourthStep.3"]).to eq({ klass: "MyFourthStep" })
  end

  it "raises if the argument is not a class" do
    expect do
      builder.start(MyFirstStep).chain("MySecondStep")
    end.to raise_error(
      ArgumentError,
      "Argument must be a valid step class"
    )
  end

  it "raises if the argument does not have an 'execute' method" do
    expect do
      builder.start(MyFirstStep).chain(Class.new)
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
      builder.start(MyFirstStep).chain(klass)
    end.to raise_error(
      ArgumentError,
      "Argument must be a valid step class"
    )
  end

  it "raises if pipeline has not been started" do
    expect do
      builder.chain(MyFirstStep)
    end.to raise_error(
      described_class::StartError,
      "Must start pipeline definition before chaining"
    )
  end
end
