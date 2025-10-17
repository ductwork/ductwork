# frozen_string_literal: true

RSpec.describe Ductwork::Branch do
  let(:branch) { described_class.new }

  describe "#start" do
    it "adds an initial step to the collection" do
      branch.start(MyFirstJob)

      expect(branch.steps.length).to eq(1)
      expect(branch.steps.sole.klass).to eq(MyFirstJob)
      expect(branch.steps.sole.type).to eq(:start)
    end
  end

  describe "#chain" do
    it "adds an initial step to the collection" do
      branch.chain(MyFirstJob)

      expect(branch.steps.length).to eq(1)
      expect(branch.steps.sole.klass).to eq(MyFirstJob)
      expect(branch.steps.sole.type).to eq(:chain)
    end
  end

  describe "#divide" do
    it "returns new branches with parent-child relationships" do
      branches = branch.divide(to: [MyFirstJob, MySecondJob])

      expect(branches.length).to eq(2)
      expect(branches[0].parents).to match_array(branch)
      expect(branches[1].parents).to match_array(branch)
      expect(branch.children).to eq(branches)
    end

    it "returns new branches with placeholder steps" do
      branches = branch.divide(to: [MyFirstJob, MySecondJob])

      expect(branches[0].steps.sole.klass).to eq(MyFirstJob)
      expect(branches[0].steps.sole.type).to eq(:divide)
      expect(branches[1].steps.sole.klass).to eq(MySecondJob)
      expect(branches[1].steps.sole.type).to eq(:divide)
    end

    it "yields the new branches if a block is given" do
      expect do |block|
        branch.divide(to: [MyFirstJob, MySecondJob], &block)
      end.to yield_control
    end
  end

  describe "#combine" do
    it "returns a new branch with parent-child relationships" do
      other_branch = described_class.new

      new_branch = branch.combine(other_branch, into: MyFirstJob)

      expect(new_branch.parents).to eq([branch, other_branch])
      expect(branch.children).to match_array(new_branch)
      expect(other_branch.children).to match_array(new_branch)
    end

    it "returns a new branch with placeholder steps" do
      other_branch = described_class.new

      new_branch = branch.combine(other_branch, into: MyFirstJob)

      expect(new_branch.steps.sole.klass).to eq(MyFirstJob)
      expect(new_branch.steps.sole.type).to eq(:combine)
    end

    it "combines multiple branches and returns a new branch" do
      second_branch = described_class.new
      third_branch = described_class.new

      new_branch = branch.combine(second_branch, third_branch, into: MyFirstJob)

      expect(new_branch.steps.sole.klass).to eq(MyFirstJob)
      expect(new_branch.parents.length).to eq(3)
      expect(branch.children.sole).to eq(new_branch)
      expect(second_branch.children.sole).to eq(new_branch)
      expect(third_branch.children.sole).to eq(new_branch)
    end
  end

  describe "#expand" do
    it "adds an initial step to the collection" do
      branch.expand(MyFirstJob)

      expect(branch.steps.length).to eq(1)
      expect(branch.steps.sole.klass).to eq(MyFirstJob)
      expect(branch.steps.sole.type).to eq(:expand)
    end
  end

  describe "#collapse" do
    it "adds an initial step to the collection" do
      branch.collapse(MyFirstJob)

      expect(branch.steps.length).to eq(1)
      expect(branch.steps.sole.klass).to eq(MyFirstJob)
      expect(branch.steps.sole.type).to eq(:collapse)
    end
  end
end
