# frozen_string_literal: true

RSpec.describe Ductwork::BranchBuilder do
  describe "#combine" do
    let(:definition) do
      {
        nodes: %w[MyFirstStep MySecondStep],
        edges: {
          "MyFirstStep" => [],
          "MySecondStep" => [],
        },
      }
    end

    it "combines the branch builder into the given step" do
      builder = described_class.new(klass: MyFirstStep, definition:)
      other_builder = described_class.new(klass: MySecondStep, definition:)

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
