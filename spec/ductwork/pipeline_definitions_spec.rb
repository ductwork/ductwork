# frozen_string_literal: true

# NOTE: this test may eventually be absorbed into branch and/or deinition
# builder specs. this test file is meant to exercise more complex pipeline
# definitions to uncover any bugs
RSpec.describe "Pipeline definitions" do # rubocop:disable RSpec/DescribeClass
  it "correctly chains steps after dividing" do
    definition = Class.new(Ductwork::Pipeline) do
      define do |pipeline|
        pipeline.start(MyFirstStep)
        pipeline.divide(to: [MySecondStep, MyThirdStep]) do |branch1, branch2|
          branch1.chain(MyFourthStep)
          branch1.combine(branch2, into: MyFifthStep)
        end
      end
    end.pipeline_definition

    branch1, branch2 = definition.branch.children
    combined_branch = definition.branch.children.first.children.sole
    expect(branch1.steps.length).to eq(2)
    expect(branch1.steps.second.klass).to eq(MyFourthStep)
    expect(branch1.children.length).to eq(1)
    expect(branch2.steps.length).to eq(1)
    expect(branch2.children.length).to eq(1)
    expect(combined_branch.steps.sole.klass).to eq(MyFifthStep)
  end

  it "correctly handles combining multiple branches" do
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
