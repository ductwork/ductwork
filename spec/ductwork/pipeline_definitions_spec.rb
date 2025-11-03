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
    pending "implementation of `Ductwork::BranchBuilder#divide`"
    definition = Class.new(Ductwork::Pipeline) do
      define do |pipeline|
        pipeline.start(MyFirstStep)
        pipeline.divide(to: [MySecondStep, MyThirdStep]) do |branch1, branch2|
          branch1.divide(to: [MyFourthStep, MyFifthStep]) do |sub_branch1, sub_branch2|
            branch2.combine(sub_branch1, sub_branch2, into: MyFirstStep)
          end
        end
      end
    end.pipeline_definition

    branch1, branch2 = definition.branch.children
    sub_branch1, sub_branch2 = branch1.children
    combined_branch = branch2.children.sole
    expect(combined_branch.parents).to contain_exactly(branch2, sub_branch1, sub_branch2)
    expect(sub_branch1.children).to match_array(combined_branch)
    expect(sub_branch2.children).to match_array(combined_branch)
  end
end
