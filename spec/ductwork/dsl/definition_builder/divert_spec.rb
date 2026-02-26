# frozen_string_literal: true

RSpec.describe Ductwork::DSL::DefinitionBuilder, "#divert" do
  let(:builder) { described_class.new }

  it "returns the builder instance" do
    returned_builder = builder.start(MyFirstStep).divert(to: { bar: MySecondStep, otherwise: MyThirdStep })

    expect(returned_builder).to eq(builder)
  end

  it "returns the builder instance when given a block" do
    returned_builder = builder # rubocop:disable Lint/EmptyBlock
                       .start(MyFirstStep)
                       .divert(to: { bar: MySecondStep, otherwise: MyThirdStep }) {}

    expect(returned_builder).to eq(builder)
  end

  it "adds edges with hash-based to map and divert type" do
    allow(SecureRandom).to receive(:hex).and_return("0", "1", "2")

    definition = builder
      .start(MyFirstStep)
      .divert(to: { bar: MySecondStep, otherwise: MyThirdStep })
      .complete

    expect(definition[:nodes]).to eq(%w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2])
    expect(definition[:edges].length).to eq(3)
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: { "bar" => "MySecondStep.1", "otherwise" => "MyThirdStep.2" }, type: :divert, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq({ klass: "MySecondStep" })
    expect(definition[:edges]["MyThirdStep.2"]).to eq({ klass: "MyThirdStep" })
  end

  it "yields branches when block given" do
    expect do |block|
      builder.start(MyFirstStep).divert(to: { bar: MySecondStep, otherwise: MyThirdStep }, &block)
    end.to yield_control
  end

  it "raises if a value is not a valid step class" do
    expect do
      builder.start(MyFirstStep).divert(to: { bar: MySecondStep, baz: "MyThirdStep" })
    end.to raise_error(
      ArgumentError,
      "Arguments must be a valid step class"
    )
  end

  it "raises if pipeline has not been started" do
    expect do
      builder.divert(to: { bar: MyFirstStep, otherwise: MySecondStep })
    end.to raise_error(
      described_class::StartError,
      "Must start pipeline definition before diverting chain"
    )
  end

  it "raises if not provided the fallback step" do
    expect do
      builder.start(MyFirstStep).divert(to: { bar: MyFirstStep })
    end.to raise_error(
      described_class::DivertError,
      "Must specify an `otherwise` branch"
    )
  end
end
