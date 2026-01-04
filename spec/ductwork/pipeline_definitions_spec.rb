# frozen_string_literal: true

# NOTE: this test may eventually be absorbed into branch and/or definition
# builder specs. this test file is meant to exercise more complex pipeline
# definitions to uncover any bugs and drive impementation
RSpec.describe "Pipeline definitions" do # rubocop:disable RSpec/DescribeClass
  it "correctly chains steps after dividing" do
    allow(SecureRandom).to receive(:hex).and_return(*%w[0 1 2 3 4 5])

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
      %w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2 MyFourthStep.3 MyFifthStep.4 MySixthStep.5]
    )
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: %w[MySecondStep.1 MyThirdStep.2], type: :divide, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq(
      { to: %w[MyFourthStep.3], type: :chain, klass: "MySecondStep" }
    )
    expect(definition[:edges]["MyThirdStep.2"]).to eq(
      { to: %w[MyFifthStep.4], type: :chain, klass: "MyThirdStep" }
    )
    expect(definition[:edges]["MyFourthStep.3"]).to eq(
      { to: %w[MySixthStep.5], type: :combine, klass: "MyFourthStep" }
    )
    expect(definition[:edges]["MyFifthStep.4"]).to eq(
      { to: %w[MySixthStep.5], type: :combine, klass: "MyFifthStep" }
    )
    expect(definition[:edges]["MySixthStep.5"]).to eq({ klass: "MySixthStep" })
  end

  it "correctly handles combining multiple branches" do
    allow(SecureRandom).to receive(:hex).and_return(*%w[0 1 2 3 4 5])

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
      %w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2 MyFourthStep.3 MyFifthStep.4 MySixthStep.5]
    )
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: %w[MySecondStep.1 MyThirdStep.2], type: :divide, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq(
      { to: %w[MyFourthStep.3 MyFifthStep.4], type: :divide, klass: "MySecondStep" }
    )
    expect(definition[:edges]["MyThirdStep.2"]).to eq(
      { to: %w[MySixthStep.5], type: :combine, klass: "MyThirdStep" }
    )
    expect(definition[:edges]["MyFourthStep.3"]).to eq(
      { to: %w[MySixthStep.5], type: :combine, klass: "MyFourthStep" }
    )
    expect(definition[:edges]["MyFifthStep.4"]).to eq(
      { to: %w[MySixthStep.5], type: :combine, klass: "MyFifthStep" }
    )
    expect(definition[:edges]["MySixthStep.5"]).to eq({ klass: "MySixthStep" })
  end

  it "correctly handles expanding and collapsing sub-branches" do
    allow(SecureRandom).to receive(:hex).and_return(*%w[0 1 2 3 4 5])

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
      %w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2 MyFourthStep.3 MyFifthStep.4 MySixthStep.5]
    )
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: %w[MySecondStep.1 MyThirdStep.2], type: :divide, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq(
      { to: %w[MyFourthStep.3], type: :chain, klass: "MySecondStep" }
    )
    expect(definition[:edges]["MyThirdStep.2"]).to eq({ klass: "MyThirdStep" })
    expect(definition[:edges]["MyFourthStep.3"]).to eq(
      { to: %w[MyFifthStep.4], type: :expand, klass: "MyFourthStep" }
    )
    expect(definition[:edges]["MyFifthStep.4"]).to eq(
      { to: %w[MySixthStep.5], type: :collapse, klass: "MyFifthStep" }
    )
    expect(definition[:edges]["MySixthStep.5"]).to eq({ klass: "MySixthStep" })
  end

  it "correctly handles reusing the same step class" do
    allow(SecureRandom).to receive(:hex).and_return(*%w[0 1 2 3])

    definition = Class.new(Ductwork::Pipeline) do
      define do |pipeline|
        pipeline
          .start(MyFirstStep)
          .chain(MyFirstStep)
          .expand(to: MyFirstStep)
          .collapse(into: MyFirstStep)
      end
    end.pipeline_definition

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep.0 MyFirstStep.1 MyFirstStep.2 MyFirstStep.3]
    )
    expect(definition[:edges].length).to eq(4)
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: ["MyFirstStep.1"], type: :chain, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MyFirstStep.1"]).to eq(
      { to: ["MyFirstStep.2"], type: :expand, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MyFirstStep.2"]).to eq(
      { to: ["MyFirstStep.3"], type: :collapse, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MyFirstStep.3"]).to eq({ klass: "MyFirstStep" })
  end

  it "correctly handles chaining while expanded before collapsing" do
    allow(SecureRandom).to receive(:hex).and_return(*%w[0 1 2 3 4])

    definition = Class.new(Ductwork::Pipeline) do
      define do |pipeline|
        pipeline
          .start(MyFirstStep)
          .expand(to: MySecondStep)
          .chain(MyThirdStep)
          .chain(MyFourthStep)
          .collapse(into: MyFifthStep)
      end
    end.pipeline_definition

    expect(definition[:nodes]).to eq(
      %w[MyFirstStep.0 MySecondStep.1 MyThirdStep.2 MyFourthStep.3 MyFifthStep.4]
    )
    expect(definition[:edges]["MyFirstStep.0"]).to eq(
      { to: ["MySecondStep.1"], type: :expand, klass: "MyFirstStep" }
    )
    expect(definition[:edges]["MySecondStep.1"]).to eq(
      { to: ["MyThirdStep.2"], type: :chain, klass: "MySecondStep" }
    )
    expect(definition[:edges]["MyThirdStep.2"]).to eq(
      { to: ["MyFourthStep.3"], type: :chain, klass: "MyThirdStep" }
    )
    expect(definition[:edges]["MyFourthStep.3"]).to eq(
      { to: ["MyFifthStep.4"], type: :collapse, klass: "MyFourthStep" }
    )
  end
end
