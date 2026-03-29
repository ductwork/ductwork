# frozen_string_literal: true

RSpec.describe Ductwork::Branch, "#advance!" do
  subject(:branch) { create(:branch, :in_progress, pipeline:) }

  let(:pipeline) do
    create(:pipeline, status: :in_progress, definition: definition)
  end
  let(:definition) do
    {
      nodes: %w[MyStepA.0 MyStepB.1],
      edges: {
        "MyStepA.0" => { to: %w[MyStepB.1], type: "expand", klass: "MyStepA" },
        "MyStepB.1" => { klass: "MyStepB" },
      },
    }.to_json
  end
  let(:step) do
    create(
      :step,
      status: :advancing,
      node: "MyStepA.0",
      klass: "MyStepA",
      branch: branch,
      pipeline: pipeline
    )
  end
  let(:transition) { create(:transition, branch:) }
  let(:advancement) { create(:advancement, transition:) }
  let(:output_payload) { { payload: }.to_json }
  let(:payload) { %w[a b c] }

  before do
    transition
    advancement
    create(:process, :current)
    create(:job, output_payload:, step:)
  end

  it "creates new steps and enqueues jobs" do
    expect do
      branch.advance!(transition, advancement)
    end.to change(Ductwork::Step, :count).by(3)
      .and change(Ductwork::Job, :count).by(3)

    steps = Ductwork::Step.last(3)
    expect(steps[0]).to be_in_progress
    expect(steps[0].node).to eq("MyStepB.1")
    expect(steps[0].klass).to eq("MyStepB")
    expect(steps[0].to_transition).to eq("expand")
    expect(steps[1]).to be_in_progress
    expect(steps[1].node).to eq("MyStepB.1")
    expect(steps[1].klass).to eq("MyStepB")
    expect(steps[1].to_transition).to eq("expand")
    expect(steps[2]).to be_in_progress
    expect(steps[2].node).to eq("MyStepB.1")
    expect(steps[2].klass).to eq("MyStepB")
    expect(steps[2].to_transition).to eq("expand")
  end

  it "passes the output payload as input arguments to the next steps" do
    branch.advance!(transition, advancement)

    input_args = Ductwork::Job.last(3).map do |job|
      JSON.parse(job.input_args).fetch("args")
    end
    expect(input_args).to contain_exactly(["a"], ["b"], ["c"])
  end

  it "completes the current branch" do
    expect do
      branch.advance!(transition, advancement)
    end.to change(branch, :status).from("in_progress").to("completed")
      .and change(branch, :completed_at).to(be_within(1.second).of(Time.current))
  end

  it "creates new child branches" do
    expect do
      branch.advance!(transition, advancement)
    end.to change(described_class, :count).by(3)
      .and change(Ductwork::BranchLink, :count).by(3)

    branches = described_class.last(3)
    expect(branches[0].parent_branches).to contain_exactly(branch)
    expect(branches[1].parent_branches).to contain_exactly(branch)
    expect(branches[2].parent_branches).to contain_exactly(branch)
  end

  it "completes the transition and advancement records" do
    branch.advance!(transition, advancement)

    be_almost_now = be_within(1.second).of(Time.current)
    transition = branch.transitions.sole
    advancement = transition.advancements.sole

    expect(transition.completed_at).to be_almost_now
    expect(advancement.completed_at).to be_almost_now
  end

  context "when the return value is empty" do
    let(:payload) { [] }

    it "completes the branch and pipeline" do
      expect do
        branch.advance!(transition, advancement)
      end.to change(branch, :status).from("in_progress").to("completed")
        .and change(pipeline, :status).from("in_progress").to("completed")
        .and change(pipeline, :completed_at).to(be_within(1.second).of(Time.current))
    end
  end

  context "when the next step cardinality is too large" do
    let(:definition) do
      {
        nodes: %w[MyStepA.0 MyStepB.1],
        edges: {
          "MyStepA.0" => { to: %w[MyStepB.1], type: "expand", klass: "MyStepA" },
          "MyStepB.1" => { klass: "MyStepB" },
        },
      }.to_json
    end

    before do
      Ductwork.configuration.steps_max_depth = 2

      create(
        :step,
        status: :advancing,
        node: "MyStepA.0",
        klass: "MyStepA",
        pipeline: pipeline
      )
    end

    it "halts the pipeline" do
      expect do
        branch.advance!(transition, advancement)
      end.not_to change(Ductwork::Step, :count)
      expect(pipeline.reload).to be_halted
    end

    it "halts all other branches" do
      create(:branch, :in_progress, pipeline:)

      expect do
        branch.advance!(transition, advancement)
      end.not_to change(Ductwork::Step, :count)
      expect(pipeline.branches).to all(be_halted)
    end
  end
end
