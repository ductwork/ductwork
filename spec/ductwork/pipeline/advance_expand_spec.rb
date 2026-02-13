# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline, "#advance" do
  subject(:pipeline) do
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
      pipeline: pipeline
    )
  end
  let(:output_payload) { { payload: }.to_json }
  let(:payload) { %w[a b c] }

  before do
    create(:job, output_payload:, step:)
  end

  it "creates a new step and enqueues a job" do
    expect do
      pipeline.advance!
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

  it "passes the output payload as input arguments to the next step" do
    pipeline.advance!

    input_args = Ductwork::Job.last(3).map do |job|
      JSON.parse(job.input_args).fetch("args")
    end
    expect(input_args).to contain_exactly(["a"], ["b"], ["c"])
  end

  it "halts the pipeline if next step cardinality is too large" do
    Ductwork.configuration.steps_max_depth = 2

    expect do
      pipeline.advance!
    end.not_to change(Ductwork::Step, :count)
    expect(pipeline.reload).to be_halted
  end

  context "when the pipeline has been divided" do
    let(:definition) do
      {
        nodes: %w[MyStepA.0 MyStepB.1 MyStepC.1 MyStepD.2 MyStepE.2],
        edges: {
          "MyStepA.0" => { to: %w[MyStepB.1 MyStepC.1], type: "divide", klass: "MyStepA" },
          "MyStepB.1" => { to: %w[MyStepD.2], type: "expand", klass: "MyStepB" },
          "MyStepC.1" => { to: %w[MyStepE.2], type: "expand", klass: "MyStepC" },
          "MyStepD.2" => { klass: "MyStepD" },
          "MyStepE.2" => { klass: "MyStepE" },
        },
      }.to_json
    end
    let(:advancing_steps) do
      [
        create(
          :step,
          status: :advancing,
          to_transition: "expand",
          node: "MyStepB.1",
          klass: "MyStepB",
          pipeline: pipeline
        ),
        create(
          :step,
          status: :advancing,
          to_transition: "expand",
          node: "MyStepC.1",
          klass: "MyStepC",
          pipeline: pipeline
        ),
      ]
    end

    before do
      step.completed!
      advancing_steps.each do |s|
        create(:job, output_payload: output_payload, step: s)
      end
    end

    it "creates a new step and job for each step in the active branch" do
      expect do
        pipeline.advance!
      end.to change(Ductwork::Step, :count).by(6)
        .and change(Ductwork::Job, :count).by(6)
      klasses = Ductwork::Step.pluck(:klass).last(6)
      expect(klasses).to eq(
        %w[MyStepD MyStepD MyStepD MyStepE MyStepE MyStepE]
      )
    end
  end

  context "when the pipeline has been expanded" do
    let(:definition) do
      {
        nodes: %w[MyStepA.0 MyStepB.1 MyStepC.2],
        edges: {
          "MyStepA.0" => { to: %w[MyStepB.1], type: "expand", klass: "MyStepA" },
          "MyStepB.1" => { to: %w[MyStepC.2], type: "expand", klass: "MyStepB" },
          "MyStepC.2" => { klass: "MyStepC" },
        },
      }.to_json
    end
    let(:advancing_steps) do
      create_list(
        :step,
        2,
        status: :advancing,
        to_transition: "expand",
        node: "MyStepB.1",
        klass: "MyStepB",
        pipeline: pipeline
      )
    end

    before do
      step.completed!
      advancing_steps.each do |s|
        create(:job, output_payload: output_payload, step: s)
      end
    end

    it "creates a new step and job for each step in the active branch" do
      expect do
        pipeline.advance!
      end.to change(Ductwork::Step, :count).by(6)
        .and change(Ductwork::Job, :count).by(6)
      klasses = Ductwork::Step.pluck(:klass).last(6)
      expect(klasses).to eq(
        %w[MyStepC MyStepC MyStepC MyStepC MyStepC MyStepC]
      )
    end
  end

  context "when there are no steps to expand to" do
    let(:payload) { %w[] }

    it "completes the pipeline" do
      be_almost_now = be_within(1.second).of(Time.current)

      expect do
        pipeline.advance!
      end.to change(pipeline, :status).from("in_progress").to("completed")
        .and change(pipeline, :completed_at).from(nil).to(be_almost_now)
    end
  end
end
