# frozen_string_literal: true

RSpec.describe Ductwork::Branch, "#advance" do
  subject(:branch) { create(:branch, :in_progress, run:) }

  let(:run) do
    create(:run, status: :in_progress, definition: definition)
  end
  let(:definition) do
    {
      nodes: %w[MyStepA.0 MyStepB.1 MyStepC.2],
      edges: {
        "MyStepA.0" => { to: %w[MyStepB.1], type: "expand", klass: "MyStepA" },
        "MyStepB.1" => { to: %w[MyStepC.2], type: "collapse", klass: "MyStepB" },
        "MyStepC.2" => { klass: "MyStepC" },
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
      run: run
    )
  end
  let(:transition) { create(:transition, branch:) }
  let(:advancement) { create(:advancement, transition:) }
  let(:output_payload) { { payload: }.to_json }
  let(:payload) { 1 }
  let(:other_branches) { create_list(:branch, 2, :completed, run:) }
  let(:parent_branch) { create(:branch, :completed, run:) }

  before do
    transition
    advancement
    create(:process, :current)
    other_step1 = create(
      :step,
      :completed,
      node: "MyStepB.1",
      klass: "MyStepB",
      run: run,
      branch: other_branches[0]
    )
    other_step2 = create(
      :step,
      :completed,
      node: "MyStepB.1",
      klass: "MyStepB",
      run: run,
      branch: other_branches[1]
    )

    Ductwork::BranchLink.create!(parent_branch: parent_branch, child_branch: branch)
    other_branches.each do |child_branch|
      Ductwork::BranchLink.create!(parent_branch:, child_branch:)
    end
    create(:job, output_payload: output_payload, step: other_step1)
    create(:job, output_payload: output_payload, step: other_step2)
    create(:job, output_payload:, step:)
  end

  it "creates a new step and enqueues a job" do
    expect do
      branch.advance!(transition, advancement)
    end.to change(Ductwork::Step, :count).by(1)
      .and change(Ductwork::Job, :count).by(1)

    step = Ductwork::Step.last
    expect(step).to be_in_progress
    expect(step.node).to eq("MyStepC.2")
    expect(step.klass).to eq("MyStepC")
    expect(step.to_transition).to eq("collapse")
  end

  it "passes the output payload as input arguments to the next step" do
    allow(Ductwork::Job).to receive(:enqueue)

    branch.advance!(transition, advancement)

    expect(Ductwork::Job).to have_received(:enqueue).with(anything, [1, 1, 1])
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
      .and change(Ductwork::BranchLink, :count).by(3)

    new_branch = described_class.last
    expect(new_branch.parent_branches).to contain_exactly(branch, *other_branches)
  end

  it "completes the transition and advancement records" do
    branch.advance!(transition, advancement)

    expect(transition.completed_at).to be_almost_now
    expect(advancement.completed_at).to be_almost_now
  end

  context "when there are incomplete sibling branches" do
    before do
      in_progress_branch = create(:branch, :in_progress, run:)
      Ductwork::BranchLink.create!(
        parent_branch: parent_branch,
        child_branch: in_progress_branch
      )
      create(
        :step,
        status: :advancing,
        node: "MyStepB.1",
        klass: "MyStepB",
        branch: in_progress_branch,
        run: run
      )
    end

    it "does not advance" do
      expect do
        branch.advance!(transition, advancement)
      end.to not_change(Ductwork::Step, :count)
        .and change(branch, :status).from("in_progress").to("completed")
        .and change(branch, :completed_at).to(be_within(1.second).of(Time.current))
    end
  end
end
