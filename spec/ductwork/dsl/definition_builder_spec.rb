# frozen_string_literal: true

RSpec.describe Ductwork::DSL::DefinitionBuilder do
  let(:builder) { described_class.new }

  describe "#on_halt" do
    it "returns the builder instance" do
      returned_builder = builder.on_halt(MyHaltStep)

      expect(returned_builder).to eq(builder)
    end

    it "adds the on halt klass to the definition as metadata" do
      allow(SecureRandom).to receive(:hex).and_return("a1b2c3d4")
      definition = builder.start(MyFirstStep).on_halt(MyHaltStep).complete

      expect(definition[:nodes]).to eq(["MyFirstStep.a1b2c3d4"])
      expect(definition[:metadata]).to eq(on_halt: { klass: "MyHaltStep" })
    end

    it "raises if the argument is not a class" do
      expect do
        builder.on_halt("MyFirstStep")
      end.to raise_error(
        ArgumentError,
        "Argument must be a valid step class"
      )
    end

    it "raises if the argument does not have an 'execute' method" do
      expect do
        builder.on_halt(Class.new)
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
        builder.on_halt(klass)
      end.to raise_error(
        ArgumentError,
        "Argument must be a valid step class"
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

    it "returns the definition" do
      allow(SecureRandom).to receive(:hex).and_return("a1b2c3d4")
      builder.start(MyFirstStep)

      definition = builder.complete

      expect(definition).to eq(
        metadata: {},
        nodes: %w[MyFirstStep.a1b2c3d4],
        edges: { "MyFirstStep.a1b2c3d4" => { klass: "MyFirstStep" } }
      )
    end
  end
end
