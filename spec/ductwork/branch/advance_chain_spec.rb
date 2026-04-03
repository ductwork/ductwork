# frozen_string_literal: true

RSpec.describe Ductwork::Branch, "#advance!" do
  subject(:branch) { create(:branch, run:) }

  let(:run) { create(:run, status: :in_progress, definition: definition) }
  let(:definition) do
    {
      nodes: %w[MyStepA.0 MyStepB.1],
      edges: {
        "MyStepA.0" => { to: %w[MyStepB.1], type: "chain", klass: "MyStepA" },
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

  it "creates a new step and enqueues a job" do
    expect do
      branch.advance!(transition, advancement)
    end.to change(Ductwork::Step, :count).by(1)
      .and change(Ductwork::Job, :count).by(1)

    step = Ductwork::Step.last
    expect(step).to be_in_progress
    expect(step.node).to eq("MyStepB.1")
    expect(step.klass).to eq("MyStepB")
    expect(step.to_transition).to eq("default")
  end

  it "passes the output payload as input arguments to the next step" do
    allow(Ductwork::Job).to receive(:enqueue)

    branch.advance!(transition, advancement)

    expect(Ductwork::Job).to have_received(:enqueue).with(anything, payload)
  end

  it "completes the transition and advancement records" do
    branch.advance!(transition, advancement)

    expect(transition.completed_at).to be_almost_now
    expect(advancement.completed_at).to be_almost_now
  end
end
