# frozen_string_literal: true

RSpec.describe Ductwork::BranchBuilder do
  describe "#chain" do
    subject(:builder) { described_class.new(klass: MyFirstStep, definition:) }

    # NOTE: we can assume the definition has at least this state because
    # this class is only used in the `DefinitionBuilder`
    let(:definition) do
      {
        nodes: %w[MyFirstStep],
        edges: {
          "MyFirstStep" => [],
        },
      }
    end

    it "returns itself" do
      instance = builder.chain(MySecondStep)

      expect(instance).to eq(builder)
    end

    it "adds a new node and edge to the definition" do
      builder.chain(MySecondStep)

      expect(definition[:nodes]).to eq(%w[MyFirstStep MySecondStep])
      expect(definition[:edges]["MyFirstStep"]).to eq(
        [
          { to: %w[MySecondStep], type: :chain },
        ]
      )
      expect(definition[:edges]["MySecondStep"]).to eq([])
    end
  end

  describe "#divide" do
    subject(:builder) { described_class.new(klass: MyFirstStep, definition:) }

    let(:definition) do
      {
        nodes: %w[MyFirstStep],
        edges: {
          "MyFirstStep" => [],
        },
      }
    end

    it "returns itself" do
      instance = builder.divide(to: [MySecondStep, MyThirdStep]) {} # rubocop:disable Lint/EmptyBlock

      expect(instance).to eq(builder)
    end

    it "adds a new node and edge to the definition" do
      builder.divide(to: [MySecondStep, MyThirdStep]) {} # rubocop:disable Lint/EmptyBlock

      expect(definition[:nodes]).to eq(%w[MyFirstStep MySecondStep MyThirdStep])
      expect(definition[:edges]["MyFirstStep"]).to eq(
        [
          { to: %w[MySecondStep MyThirdStep], type: :divide },
        ]
      )
      expect(definition[:edges]["MySecondStep"]).to eq([])
      expect(definition[:edges]["MyThirdStep"]).to eq([])
    end

    it "yields the sub-branches to the block" do
      expect do |block|
        builder.divide(to: [MySecondStep, MyThirdStep], &block)
      end.to yield_control
    end
  end

  describe "#combine" do
    subject(:builder) { described_class.new(klass: MyFirstStep, definition:) }

    let(:other_builder) { described_class.new(klass: MySecondStep, definition:) }
    # NOTE: we can assume the definition has at least this state because
    # this class is only used in the `DefinitionBuilder`
    let(:definition) do
      {
        nodes: %w[MyFirstStep MySecondStep],
        edges: {
          "MyFirstStep" => [],
          "MySecondStep" => [],
        },
      }
    end

    it "returns itself" do
      instance = builder.combine(other_builder, into: MyThirdStep)

      expect(instance).to eq(builder)
    end

    it "combines the branch builder into the given step" do
      builder.combine(other_builder, into: MyThirdStep)

      expect(definition[:nodes]).to eq(%w[MyFirstStep MySecondStep MyThirdStep])
      expect(definition[:edges]["MyFirstStep"].sole).to eq(
        {
          to: %w[MyThirdStep],
          type: :combine,
        }
      )
      expect(definition[:edges]["MySecondStep"].sole).to eq(
        {
          to: %w[MyThirdStep],
          type: :combine,
        }
      )
    end

    it "combines multiple branch builders into the given step" do
      builder, *other_builders = [
        described_class.new(klass: MyFirstStep, definition:),
        described_class.new(klass: MySecondStep, definition:),
        described_class.new(klass: MyThirdStep, definition:),
      ]
      definition[:nodes].push("MyThirdStep")
      definition[:edges]["MyThirdStep"] = []

      builder.combine(*other_builders, into: MyFourthStep)

      expect(definition[:edges]["MyFirstStep"].sole).to eq(
        {
          to: %w[MyFourthStep],
          type: :combine,
        }
      )
      expect(definition[:edges]["MySecondStep"].sole).to eq(
        {
          to: %w[MyFourthStep],
          type: :combine,
        }
      )
      expect(definition[:edges]["MyThirdStep"].sole).to eq(
        {
          to: %w[MyFourthStep],
          type: :combine,
        }
      )
      expect(definition[:edges]["MyFourthStep"]).to eq([])
    end
  end
end
