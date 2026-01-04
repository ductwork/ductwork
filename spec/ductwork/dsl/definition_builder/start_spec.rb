# frozen_string_literal: true

RSpec.describe Ductwork::DSL::DefinitionBuilder, "#start" do
  let(:builder) { described_class.new }

  it "returns the builder instance" do
    returned_builder = builder.start(MyFirstStep)

    expect(returned_builder).to eq(builder)
  end

  it "adds the initial branch and step to the definition" do
    allow(SecureRandom).to receive(:hex).and_return("a1b2c3d4")

    definition = builder.start(MyFirstStep).complete

    expect(definition[:nodes]).to eq(["MyFirstStep.a1b2c3d4"])
    expect(definition[:edges].length).to eq(1)
    expect(definition[:edges]["MyFirstStep.a1b2c3d4"]).to eq({ klass: "MyFirstStep" })
  end

  it "raises if the argument is not a class" do
    expect do
      builder.start("MyFirstStep")
    end.to raise_error(
      ArgumentError,
      "Argument must be a valid step class"
    )
  end

  it "raises if the argument does not have an 'execute' method" do
    expect do
      builder.start(Class.new)
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
      builder.start(klass)
    end.to raise_error(
      ArgumentError,
      "Argument must be a valid step class"
    )
  end

  it "raises if called more than once" do
    expect do
      builder.start(MyFirstStep).start(MyFirstStep)
    end.to raise_error(
      described_class::StartError,
      "Can only start pipeline definition once"
    )
  end
end
