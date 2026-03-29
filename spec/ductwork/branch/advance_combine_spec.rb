# frozen_string_literal: true

RSpec.describe Ductwork::Branch, "#advance" do
  subject(:branch) { create(:branch, :in_progress, pipeline:) }

  let(:pipeline) do
    create(:pipeline, status: :in_progress, definition: definition)
  end
  let(:definition) do
    {
      nodes: %w[MyStepA.0 MyStepB.1 MyStepC.2 MyStepD.3],
      edges: {
        "MyStepA.0" => { to: %w[MyStepB.1 MyStepC.2], type: "divide", klass: "MyStepA" },
        "MyStepB.1" => { to: %w[MyStepD.3], type: "combine", klass: "MyStepB" },
        "MyStepC.2" => { to: %w[MyStepD.3], type: "combine", klass: "MyStepC" },
        "MyStepD.3" => { klass: "MyStepD" },
      },
    }.to_json
  end
  let(:step) do
    create(
      :step,
      status: :advancing,
      node: "MyStepB.1",
      klass: "MyStepB",
      branch: branch,
      pipeline: pipeline
    )
  end
  let(:transition) { create(:transition, branch:) }
  let(:advancement) { create(:advancement, transition:) }
  let(:parent_branch) { create(:branch, :completed, pipeline:) }
  let(:other_branch) { create(:branch, :completed, pipeline:) }
  let(:output_payload) { { payload: }.to_json }
  let(:payload) { 1 }

  before do
    transition
    advancement
    create(:process, :current)
    other_step = create(
      :step,
      status: :completed,
      node: "MyStepC.2",
      klass: "MyStepC",
      branch: other_branch,
      pipeline: pipeline
    )
    Ductwork::BranchLink.create!(parent_branch: parent_branch, child_branch: branch)
    Ductwork::BranchLink.create!(parent_branch: parent_branch, child_branch: other_branch)
    create(:job, output_payload:, step:)
    create(:job, output_payload: output_payload, step: other_step)
  end

  it "creates a new step and enqueues a job" do
    expect do
      branch.advance!(transition, advancement)
    end.to change(Ductwork::Step, :count).by(1)
      .and change(Ductwork::Job, :count).by(1)

    step = Ductwork::Step.last
    expect(step).to be_in_progress
    expect(step.node).to eq("MyStepD.3")
    expect(step.klass).to eq("MyStepD")
    expect(step.to_transition).to eq("combine")
  end

  it "passes the output payloads as input arguments to the next step" do
    allow(Ductwork::Job).to receive(:enqueue)

    branch.advance!(transition, advancement)

    expect(Ductwork::Job).to have_received(:enqueue).with(anything, [1, 1])
  end

  it "completes the current branch" do
    expect do
      branch.advance!(transition, advancement)
    end.to change(branch, :status).from("in_progress").to("completed")
      .and change(branch, :completed_at).to(be_within(1.second).of(Time.current))
  end

  it "creates a new child branch" do
    expect do
      branch.advance!(transition, advancement)
    end.to change(described_class, :count).by(1)
      .and change(Ductwork::BranchLink, :count).by(2)

    new_branch = described_class.last
    expect(new_branch.parent_branches).to contain_exactly(branch, other_branch)
  end

  it "completes the transition and advancement records" do
    branch.advance!(transition, advancement)

    be_almost_now = be_within(1.second).of(Time.current)
    transition = branch.transitions.sole
    advancement = transition.advancements.sole

    expect(transition.completed_at).to be_almost_now
    expect(advancement.completed_at).to be_almost_now
  end
end
