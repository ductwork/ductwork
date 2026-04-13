# frozen_string_literal: true

RSpec.describe Ductwork::Branch, "#advance!" do
  subject(:branch) { create(:branch, :in_progress, run:) }

  let(:run) do
    create(:run, status: :in_progress, definition: definition)
  end
  let(:definition) do
    {
      nodes: %w[MyStepA.0 MyStepB.1 MyStepC.2 MyStepD.3],
      edges: {
        "MyStepA.0" => {
          to: { "bar" => "MyStepB.1", "baz" => "MyStepC.2", "otherwise" => "MyStepD.3" },
          type: "divert",
          klass: "MyStepA",
        },
        "MyStepB.1" => { klass: "MyStepB" },
        "MyStepC.2" => { klass: "MyStepC" },
        "MyStepD.3" => { klass: "MyStepD" },
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
  let(:payload) { "bar" }

  before do
    transition
    advancement
    create(:process, :current)
    create(:job, output_payload:, step:)
  end

  it "routes to the correct next step when return value matches" do
    expect do
      branch.advance!(transition, advancement)
    end.to change(Ductwork::Step, :count).by(1)
      .and change(Ductwork::Job, :count).by(1)

    new_step = Ductwork::Step.last
    expect(new_step).to be_in_progress
    expect(new_step.node).to eq("MyStepB.1")
    expect(new_step.klass).to eq("MyStepB")
    expect(new_step.to_transition).to eq("divert")
    expect(new_step.branch).to eq(branch)
  end

  it "passes the output payload as input arguments to the next steps" do
    allow(Ductwork::Job).to receive(:enqueue)

    branch.advance!(transition, advancement)

    expect(Ductwork::Job).to have_received(:enqueue).with(anything, payload)
  end

  it "completes the transition and advancement records" do
    branch.advance!(transition, advancement)

    expect(transition.completed_at).to be_almost_now
    expect(advancement.completed_at).to be_almost_now
  end

  context "when there is no match and no otherwise branch" do
    let(:definition) do
      {
        nodes: %w[MyStepA.0 MyStepB.1],
        edges: {
          "MyStepA.0" => {
            to: { "bar" => "MyStepB.1" },
            type: "divert",
            klass: "MyStepA",
          },
          "MyStepB.1" => { klass: "MyStepB" },
        },
      }.to_json
    end
    let(:output_payload) { { payload: "unknown" }.to_json }

    it "halts the branch, run, and pipeline" do
      expect do
        branch.advance!(transition, advancement)
      end.not_to change(Ductwork::Step, :count)

      expect(branch.reload).to be_halted
      expect(branch.halt_reason).to eq("condition_unmatched")
      expect(run.reload).to be_halted
      expect(run.pipeline).to be_halted
    end
  end
end
