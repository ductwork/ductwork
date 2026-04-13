# frozen_string_literal: true

RSpec.describe Ductwork::Branch, "#advance!" do
  subject(:branch) { create(:branch, :in_progress, run:) }

  let(:run) { create(:run, status: :in_progress, definition: definition) }
  let(:definition) do
    {
      nodes: %w[MyStepA.0 MyStepB.1 MyStepC.1],
      edges: {
        "MyStepA.0" => { to: %w[MyStepB.1 MyStepC.1], type: "divide", klass: "MyStepA" },
        "MyStepB.1" => { klass: "MyStepB" },
        "MyStepC.1" => { klass: "MyStepC" },
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
      run: run
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
    end.to change(Ductwork::Step, :count).by(2)
      .and change(Ductwork::Job, :count).by(2)

    steps = Ductwork::Step.last(2)
    expect(steps[0]).to be_in_progress
    expect(steps[0].node).to eq("MyStepB.1")
    expect(steps[0].klass).to eq("MyStepB")
    expect(steps[0].to_transition).to eq("divide")
    expect(steps[1]).to be_in_progress
    expect(steps[1].node).to eq("MyStepC.1")
    expect(steps[1].klass).to eq("MyStepC")
    expect(steps[1].to_transition).to eq("divide")
  end

  it "passes the output payload as input arguments to the next steps" do
    allow(Ductwork::Job).to receive(:enqueue)

    branch.advance!(transition, advancement)

    expect(Ductwork::Job).to have_received(:enqueue).with(anything, payload).twice
  end

  it "completes the current branch" do
    expect do
      branch.advance!(transition, advancement)
    end.to change(branch, :status).from("in_progress").to("completed")
  end

  it "creates new child branches" do
    expect do
      branch.advance!(transition, advancement)
    end.to change(described_class, :count).by(2)
      .and change(Ductwork::BranchLink, :count).by(2)

    branches = described_class.last(2)
    expect(branches.first.parent_branches).to contain_exactly(branch)
    expect(branches.first.pipeline_klass).to eq(branch.pipeline_klass)
    expect(branches.last.parent_branches).to contain_exactly(branch)
    expect(branches.last.pipeline_klass).to eq(branch.pipeline_klass)
  end

  it "completes the transition and advancement records" do
    branch.advance!(transition, advancement)

    expect(transition.completed_at).to be_almost_now
    expect(advancement.completed_at).to be_almost_now
  end

  context "when the next step cardinality is too large" do
    let(:definition) do
      {
        nodes: %w[MyStepA.0 MyStepB.1],
        edges: {
          "MyStepA.0" => { to: %w[MyStepB.1 MyStepB.1 MyStepB.1], type: "divide", klass: "MyStepA" },
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
        run: run
      )
    end

    it "halts the branch, run, and pipeline" do
      expect do
        branch.advance!(transition, advancement)
      end.not_to change(Ductwork::Step, :count)

      expect(branch.reload).to be_halted
      expect(branch.halt_reason).to eq("max_fanout_exceeded")
      expect(run.reload).to be_halted
      expect(run.pipeline.reload).to be_halted
    end
  end
end
