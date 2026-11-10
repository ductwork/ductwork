# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline, "#revive! across a fan-in" do
  subject(:pipeline) { create(:pipeline, :halted) }

  let(:previous_run) do
    create(
      :run,
      :halted,
      pipeline: pipeline,
      pipeline_klass: pipeline.klass,
      definition: definition
    )
  end
  let(:parent_branch) { create(:branch, :completed, run: previous_run) }

  def output(value)
    JSON.dump({ payload: value })
  end

  def create_sibling(node, branch_traits, step_traits, **branch_attributes)
    branch = create(:branch, *branch_traits, run: previous_run, **branch_attributes)
    step = create(
      :step,
      *step_traits,
      node: node,
      klass: node.split(".").first,
      run: previous_run,
      branch: branch
    )
    create(:branch_link, parent_branch: parent_branch, child_branch: branch)
    step
  end

  def create_completed_sibling(node)
    step = create_sibling(node, [:completed], [:completed])
    create(:job, step: step, klass: step.klass, output_payload: output(1))
  end

  def create_halted_sibling(node)
    step = create_sibling(node, [:halted], [:failed], halt_reason: "job_retries_exhausted")
    create(:job, step: step, klass: step.klass)
  end

  def finish_revived_sibling!(value)
    branch = pipeline.current_run.branches.in_progress.sole
    step = branch.latest_step
    step.job.update!(output_payload: output(value), completed_at: Time.current)
    step.update!(status: :advancing)
    transition = create(:transition, branch: branch, in_step: step, out_step: nil)

    branch.advance!(transition, create(:advancement, transition:))
  end

  def fan_in_input_args(node)
    job = pipeline.current_run.steps.find_by(node:).job

    JSON.parse(job.input_args).fetch("args").sole
  end

  before do
    create(:process, :current)
    create(
      :step,
      :completed,
      node: "MyStepA.0",
      klass: "MyStepA",
      run: previous_run,
      branch: parent_branch
    )
  end

  context "with a combine" do
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

    before do
      create_completed_sibling("MyStepB.1")
      create_halted_sibling("MyStepC.2")
    end

    it "feeds every sibling's output to the combined step" do
      pipeline.revive!
      finish_revived_sibling!(2)

      expect(fan_in_input_args("MyStepD.3")).to contain_exactly(1, 2)
    end
  end

  context "with a chain before the combine" do
    let(:definition) do
      {
        nodes: %w[MyStepA.0 MyStepB.1 MyStepC.2 MyStepD.3 MyStepE.4],
        edges: {
          "MyStepA.0" => { to: %w[MyStepB.1 MyStepC.2], type: "divide", klass: "MyStepA" },
          "MyStepB.1" => { to: %w[MyStepE.4], type: "chain", klass: "MyStepB" },
          "MyStepE.4" => { to: %w[MyStepD.3], type: "combine", klass: "MyStepE" },
          "MyStepC.2" => { to: %w[MyStepD.3], type: "combine", klass: "MyStepC" },
          "MyStepD.3" => { klass: "MyStepD" },
        },
      }.to_json
    end
    let(:chained_branch) { first_chained_step.branch }
    let(:first_chained_step) do
      create_sibling("MyStepB.1", [:completed], [:completed]).tap do |step|
        step.update!(started_at: 2.minutes.ago)
      end
    end
    let(:last_chained_step) do
      create(
        :step,
        :completed,
        node: "MyStepE.4",
        klass: "MyStepE",
        run: previous_run,
        branch: chained_branch,
        started_at: 1.minute.ago
      )
    end

    before do
      create(:job, step: first_chained_step, klass: "MyStepB", output_payload: output(1))
      create(:job, step: last_chained_step, klass: "MyStepE", output_payload: output(3))
      create_halted_sibling("MyStepC.2")
    end

    it "keeps the copied steps in their original order" do
      pipeline.revive!

      copied_branch = pipeline.current_run.branches.completed.find do |branch|
        branch.steps.exists?(node: "MyStepE.4")
      end
      copied_steps = copied_branch.steps.order(:started_at)

      expect(copied_steps.map(&:node)).to eq(%w[MyStepB.1 MyStepE.4])
      expect(copied_steps.map(&:started_at).uniq.length).to eq(2)
      expect(copied_branch.latest_step.node).to eq("MyStepE.4")
    end

    it "feeds the last chained step's output to the combined step" do
      pipeline.revive!
      finish_revived_sibling!(2)

      expect(fan_in_input_args("MyStepD.3")).to contain_exactly(3, 2)
    end
  end

  context "with a collapse" do
    let(:definition) do
      {
        nodes: %w[MyStepA.0 MyStepB.1 MyStepC.2],
        edges: {
          "MyStepA.0" => { to: %w[MyStepB.1], type: "expand", klass: "MyStepA" },
          "MyStepB.1" => { to: %w[MyStepC.2], type: "collapse", klass: "MyStepB", barrier_node: "MyStepA.0" },
          "MyStepC.2" => { klass: "MyStepC" },
        },
      }.to_json
    end

    before do
      2.times { create_completed_sibling("MyStepB.1") }
      create_halted_sibling("MyStepB.1")
    end

    it "feeds every sibling's output to the collapsed step" do
      pipeline.revive!
      finish_revived_sibling!(2)

      expect(fan_in_input_args("MyStepC.2")).to contain_exactly(1, 1, 2)
    end
  end
end
