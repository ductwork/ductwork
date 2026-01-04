# frozen_string_literal: true

RSpec.describe Ductwork::DSL::DefinitionBuilder, "#divide" do
  let(:builder) { described_class.new }

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
    allow(SecureRandom).to receive(:hex).and_return("0", "1", "2")

    definition = builder
      .start(MyFirstStep)
      .divide(to: [MySecondStep, MyThirdStep])
      .complete

    expect(definition[:nodes]).to eq(%w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2])
    expect(definition[:edges].length).to eq(3)
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: %w[MySecondStep.1 MyThirdStep.2], type: :divide, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq({ klass: "MySecondStep" })
    expect(definition[:edges]["MyThirdStep.2"]).to eq({ klass: "MyThirdStep" })
  end

  it "yields the new branches if a block is given" do
    expect do |block|
      builder.start(MyFirstStep).divide(to: [MySecondStep, MyThirdStep], &block)
    end.to yield_control
  end

  it "raises if the argument is not a class" do
    expect do
      builder.start(MyFirstStep).divide(to: [MySecondStep, "MyThirdStep"])
    end.to raise_error(
      ArgumentError,
      "Arguments must be a valid step class"
    )
  end

  it "raises if the argument does not have an 'execute' method" do
    expect do
      builder.start(MyFirstStep).divide(to: [Class.new, MyThirdStep])
    end.to raise_error(
      ArgumentError,
      "Arguments must be a valid step class"
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
      builder.divide(to: [MyFirstStep, MySecondStep])
    end.to raise_error(
      described_class::StartError,
      "Must start pipeline definition before dividing chain"
    )
  end
end
