# frozen_string_literal: true

RSpec.describe Ductwork::Branch, "#advance" do
  subject(:branch) { create(:branch, :in_progress, run:) }

  let(:run) do
    create(:run, status: :in_progress, definition: definition)
  end
  let(:definition) do
    {
      nodes: %w[MyStepA.0 MyStepB.1 MyStepC.2 MyStepD.3],
      edges: {
        "MyStepA.0" => {
          to: { "bar" => "MyStepB.1", "otherwise" => "MyStepC.2" },
          type: "divert",
          klass: "MyStepA",
        },
        "MyStepB.1" => { to: %w[MyStepD.3], type: "converge", klass: "MyStepB" },
        "MyStepC.2" => { to: %w[MyStepD.3], type: "converge", klass: "MyStepC" },
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
      run: run
    )
  end
  let(:transition) { create(:transition, branch:) }
  let(:advancement) { create(:advancement, transition:) }
  let(:other_branch) { create(:branch, :completed, run:) }
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
      run: run
    )
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
    expect(step.to_transition).to eq("converge")
  end

  it "passes the output payloads as input arguments to the next step" do
    allow(Ductwork::Job).to receive(:enqueue)

    branch.advance!(transition, advancement)

    expect(Ductwork::Job).to have_received(:enqueue).with(anything, 1)
  end

  it "completes the transition and advancement records" do
    branch.advance!(transition, advancement)

    expect(transition.completed_at).to be_almost_now
    expect(advancement.completed_at).to be_almost_now
  end
end
