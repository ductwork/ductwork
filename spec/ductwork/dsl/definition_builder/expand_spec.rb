# frozen_string_literal: true

RSpec.describe Ductwork::DSL::DefinitionBuilder, "#expand" do
  let(:builder) { described_class.new }

  it "returns the builder instance" do
    returned_builder = builder.start(MyFirstStep).expand(to: MySecondStep)

    expect(returned_builder).to eq(builder)
  end

  it "adds a step to the definition" do
    allow(SecureRandom).to receive(:hex).and_return("0", "1")

    definition = builder.start(MyFirstStep).expand(to: MySecondStep).complete

    expect(definition[:nodes]).to eq(%w[MyFirstStep.0 MySecondStep.1])
    expect(definition[:edges].length).to eq(2)
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: %w[MySecondStep.1], type: :expand, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq({ klass: "MySecondStep" })
  end

  it "raises if the argument is not a class" do
    expect do
      builder.start(MyFirstStep).expand(to: "MySecondStep")
    end.to raise_error(
      ArgumentError,
      "Argument must be a valid step class"
    )
  end

  it "raises if the argument does not have an 'execute' method" do
    expect do
      builder.start(MyFirstStep).expand(to: Class.new)
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
      builder.start(MyFirstStep).expand(to: klass)
    end.to raise_error(
      ArgumentError,
      "Argument must be a valid step class"
    )
  end

  it "raises if pipeline has not been started" do
    expect do
      builder.expand(to: MyFirstStep)
    end.to raise_error(
      described_class::StartError,
      "Must start pipeline definition before expanding chain"
    )
  end
end
