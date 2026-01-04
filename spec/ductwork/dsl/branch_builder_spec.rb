# frozen_string_literal: true

RSpec.describe Ductwork::DSL::BranchBuilder do
  describe "#chain" do
    subject(:builder) { described_class.new(last_node:, definition:) }

    let(:last_node) { "MyFirstStep.a1b2c3d4" }
    # NOTE: we can assume the definition has at least this state because
    # this class is only used in the `DefinitionBuilder`
    let(:definition) do
      {
        nodes: %w[MyFirstStep.a1b2c3d4],
        edges: {
          "MyFirstStep.a1b2c3d4" => { klass: "MyFirstStep" },
        },
      }
    end

    it "returns itself" do
      instance = builder.chain(MySecondStep)

      expect(instance).to eq(builder)
    end

    it "adds a new node and edge to the definition" do
      allow(SecureRandom).to receive(:hex).and_return("1982371b")
      builder.chain(MySecondStep)

      expect(definition[:nodes]).to eq(%w[MyFirstStep.a1b2c3d4 MySecondStep.1982371b])
      expect(definition[:edges]["MyFirstStep.a1b2c3d4"]).to eq(
        { to: %w[MySecondStep.1982371b], type: :chain, klass: "MyFirstStep" }
      )
      expect(definition[:edges]["MySecondStep.1982371b"]).to eq({ klass: "MySecondStep" })
    end
  end

  describe "#divide" do
    subject(:builder) { described_class.new(last_node:, definition:) }

    let(:last_node) { "MyFirstStep.a1b2c3d4" }
    # NOTE: we can assume the definition has at least this state because
    # this class is only used in the `DefinitionBuilder`
    let(:definition) do
      {
        nodes: %w[MyFirstStep.a1b2c3d4],
        edges: {
          "MyFirstStep.a1b2c3d4" => { klass: "MyFirstStep" },
        },
      }
    end
    let(:hex1) { "23753ad9" }
    let(:hex2) { "d530ee45" }

    before do
      allow(SecureRandom).to receive(:hex).and_return(hex1, hex2)
    end

    it "returns itself" do
      instance = builder.divide(to: [MySecondStep, MyThirdStep]) {} # rubocop:disable Lint/EmptyBlock

      expect(instance).to eq(builder)
    end

    it "adds a new node and edge to the definition" do
      builder.divide(to: [MySecondStep, MyThirdStep]) {} # rubocop:disable Lint/EmptyBlock

      expect(definition[:nodes]).to eq(
        ["MyFirstStep.a1b2c3d4", "MySecondStep.#{hex1}", "MyThirdStep.#{hex2}"]
      )
      expect(definition[:edges]["MyFirstStep.a1b2c3d4"]).to eq(
        { to: ["MySecondStep.#{hex1}", "MyThirdStep.#{hex2}"], type: :divide, klass: "MyFirstStep" }
      )
      expect(definition[:edges]["MySecondStep.#{hex1}"]).to eq({ klass: "MySecondStep" })
      expect(definition[:edges]["MyThirdStep.#{hex2}"]).to eq({ klass: "MyThirdStep" })
    end

    it "yields the sub-branches to the block" do
      expect do |block|
        builder.divide(to: [MySecondStep, MyThirdStep], &block)
      end.to yield_control
    end
  end

  describe "#combine" do
    subject(:builder) { described_class.new(last_node:, definition:) }

    let(:other_builder) do
      described_class.new(last_node: second_last_node, definition: definition)
    end
    let(:last_node) { "MyFirstStep.a1b2c3d4" }
    let(:second_last_node) { "MySecondStep.10923fac" }
    # NOTE: we can assume the definition has at least this state because
    # this class is only used in the `DefinitionBuilder`
    let(:definition) do
      {
        nodes: [last_node, second_last_node],
        edges: {
          last_node => { klass: "MyFirstStep" },
          second_last_node => { klass: "MySecondStep" },
        },
      }
    end

    it "returns itself" do
      instance = builder.combine(other_builder, into: MyThirdStep)

      expect(instance).to eq(builder)
    end

    it "combines the branch builder into the given step" do
      allow(SecureRandom).to receive(:hex).and_return("2")
      builder.combine(other_builder, into: MyThirdStep)

      expect(definition[:nodes]).to eq(
        [last_node, second_last_node, "MyThirdStep.2"]
      )
      expect(definition[:edges][last_node]).to eq(
        { to: %w[MyThirdStep.2], type: :combine, klass: "MyFirstStep" }
      )
      expect(definition[:edges][second_last_node]).to eq(
        { to: %w[MyThirdStep.2], type: :combine, klass: "MySecondStep" }
      )
    end

    it "combines multiple branch builders into the given step" do
      allow(SecureRandom).to receive(:hex).and_return("2")
      builder, *other_builders = [
        described_class.new(last_node:, definition:),
        described_class.new(last_node: second_last_node, definition: definition),
        described_class.new(last_node: "MyThirdStep.1", definition: definition),
      ]
      definition[:nodes].push("MyThirdStep.1")
      definition[:edges]["MyThirdStep.1"] = { klass: "MyThirdStep" }

      builder.combine(*other_builders, into: MyFourthStep)

      expect(definition[:edges][last_node]).to eq(
        { to: %w[MyFourthStep.2], type: :combine, klass: "MyFirstStep" }
      )
      expect(definition[:edges][second_last_node]).to eq(
        { to: %w[MyFourthStep.2], type: :combine, klass: "MySecondStep" }
      )
      expect(definition[:edges]["MyThirdStep.1"]).to eq(
        { to: %w[MyFourthStep.2], type: :combine, klass: "MyThirdStep" }
      )
      expect(definition[:edges]["MyFourthStep.2"]).to eq({ klass: "MyFourthStep" })
    end
  end

  describe "#expand" do
    subject(:builder) { described_class.new(last_node:, definition:) }

    let(:last_node) { "MyFirstStep.a1b2c3d4" }
    # NOTE: we can assume the definition has at least this state because
    # this class is only used in the `DefinitionBuilder`
    let(:definition) do
      {
        nodes: [last_node],
        edges: {
          last_node => { klass: "MyFirstStep" },
        },
      }
    end

    it "returns itself" do
      instance = builder.expand(to: MySecondStep)

      expect(instance).to eq(builder)
    end

    it "adds a new node and edge to the definition" do
      allow(SecureRandom).to receive(:hex).and_return("1")
      builder.expand(to: MySecondStep)

      expect(definition[:nodes]).to eq([last_node, "MySecondStep.1"])
      expect(definition[:edges][last_node]).to eq(
        { to: ["MySecondStep.1"], type: :expand, klass: "MyFirstStep" }
      )
      expect(definition[:edges]["MySecondStep.1"]).to eq({ klass: "MySecondStep" })
    end
  end

  describe "#collapse" do
    subject(:builder) { described_class.new(last_node:, definition:) }

    let(:last_node) { "MyFirstStep.a1b2c3d4" }
    # NOTE: we can assume the definition has at least this state because
    # this class is only used in the `DefinitionBuilder`
    let(:definition) do
      {
        nodes: [last_node],
        edges: {
          last_node => { klass: "MyFirstStep" },
        },
      }
    end

    before do
      allow(SecureRandom).to receive(:hex).and_return("1", "2")
      builder.expand(to: MySecondStep)
    end

    it "returns itself" do
      instance = builder.collapse(into: MyThirdStep)

      expect(instance).to eq(builder)
    end

    it "adds a new node and edge to the definition" do
      builder.collapse(into: MyThirdStep)

      expect(definition[:nodes]).to eq(
        [last_node, "MySecondStep.1", "MyThirdStep.2"]
      )
      expect(definition[:edges][last_node]).to eq(
        { to: %w[MySecondStep.1], type: :expand, klass: "MyFirstStep" }
      )
      expect(definition[:edges]["MySecondStep.1"]).to eq(
        { to: %w[MyThirdStep.2], type: :collapse, klass: "MySecondStep" }
      )
      expect(definition[:edges]["MyThirdStep.2"]).to eq({ klass: "MyThirdStep" })
    end

    it "raises when the branch definition has not been expanded" do
      definition = {
        nodes: %w[MyFirstStep.a1b2c3d4],
        edges: { "MyFirstStep.a1b2c3d4" => { klass: "MyFirstStep" } },
      }
      builder = described_class.new(last_node: "MyFirstStep.a1b2c3d4", definition: definition)

      expect do
        builder.collapse(into: MySecondStep)
      end.to raise_error(
        described_class::CollapseError,
        "Must expand pipeline definition before collapsing steps"
      )
    end
  end
end
