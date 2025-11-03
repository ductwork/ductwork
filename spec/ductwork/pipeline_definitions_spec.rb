# frozen_string_literal: true

# NOTE: this test may eventually be absorbed into branch and/or definition
# builder specs. this test file is meant to exercise more complex pipeline
# definitions to uncover any bugs and drive impementation
RSpec.describe "Pipeline definitions" do # rubocop:disable RSpec/DescribeClass
  it "correctly chains steps after dividing" do
    definition = Class.new(Ductwork::Pipeline) do
      define do |pipeline|
        pipeline.start(MyFirstStep)
        pipeline.divide(to: [MySecondStep, MyThirdStep]) do |branch1, branch2|
          branch1.chain(MyFourthStep)
          branch2.chain(MyFifthStep)
          branch1.combine(branch2, into: MySixthStep)
        end
      end
    end.pipeline_definition

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep MySecondStep MyThirdStep MyFourthStep MyFifthStep MySixthStep]
    )
    expect(definition[:edges]["MyFirstStep"]).to eq(
      [
        { to: %w[MySecondStep MyThirdStep], type: :divide },
      ]
    )
    expect(definition[:edges]["MySecondStep"]).to eq(
      [
        { to: %w[MyFourthStep], type: :chain },
      ]
    )
    expect(definition[:edges]["MyThirdStep"]).to eq(
      [
        { to: %w[MyFifthStep], type: :chain },
      ]
    )
    expect(definition[:edges]["MyFourthStep"]).to eq(
      [
        { to: %w[MySixthStep], type: :combine },
      ]
    )
    expect(definition[:edges]["MyFifthStep"]).to eq(
      [
        { to: %w[MySixthStep], type: :combine },
      ]
    )
    expect(definition[:edges]["MySixthStep"]).to eq([])
  end

  it "correctly handles combining multiple branches" do
    definition = Class.new(Ductwork::Pipeline) do
      define do |pipeline|
        pipeline.start(MyFirstStep)
        pipeline.divide(to: [MySecondStep, MyThirdStep]) do |branch1, branch2|
          branch1.divide(to: [MyFourthStep, MyFifthStep]) do |sub_branch1, sub_branch2|
            branch2.combine(sub_branch1, sub_branch2, into: MySixthStep)
          end
        end
      end
    end.pipeline_definition

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep MySecondStep MyThirdStep MyFourthStep MyFifthStep MySixthStep]
    )
    expect(definition[:edges]["MyFirstStep"]).to eq(
      [
        { to: %w[MySecondStep MyThirdStep], type: :divide },
      ]
    )
    expect(definition[:edges]["MySecondStep"]).to eq(
      [
        { to: %w[MyFourthStep MyFifthStep], type: :divide },
      ]
    )
    expect(definition[:edges]["MyThirdStep"]).to eq(
      [
        { to: %w[MySixthStep], type: :combine },
      ]
    )
    expect(definition[:edges]["MyFourthStep"]).to eq(
      [
        { to: %w[MySixthStep], type: :combine },
      ]
    )
    expect(definition[:edges]["MyFifthStep"]).to eq(
      [
        { to: %w[MySixthStep], type: :combine },
      ]
    )
    expect(definition[:edges]["MySixthStep"]).to eq([])
  end

  it "correctly handles expanding and collapsing sub-branches" do
    definition = Class.new(Ductwork::Pipeline) do
      define do |pipeline|
        pipeline.start(MyFirstStep)
        pipeline.divide(to: [MySecondStep, MyThirdStep]) do |branch1, _branch2|
          branch1
            .chain(MyFourthStep)
            .expand(to: MyFifthStep)
            .collapse(into: MySixthStep)
        end
      end
    end.pipeline_definition

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep MySecondStep MyThirdStep MyFourthStep MyFifthStep MySixthStep]
    )
    expect(definition[:edges]["MyFirstStep"]).to eq(
      [
        { to: %w[MySecondStep MyThirdStep], type: :divide },
      ]
    )
    expect(definition[:edges]["MySecondStep"]).to eq(
      [
        { to: %w[MyFourthStep], type: :chain },
      ]
    )
    expect(definition[:edges]["MyThirdStep"]).to eq([])
    expect(definition[:edges]["MyFourthStep"]).to eq(
      [
        { to: %w[MyFifthStep], type: :expand },
      ]
    )
    expect(definition[:edges]["MyFifthStep"]).to eq(
      [
        { to: %w[MySixthStep], type: :collapse },
      ]
    )
    expect(definition[:edges]["MySixthStep"]).to eq([])
  end
end
