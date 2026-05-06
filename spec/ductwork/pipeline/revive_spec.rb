# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline, "#revive!" do
  subject(:pipeline) { create(:pipeline, :halted, klass:) }

  let(:klass) { "MyPipeline" }
  let(:previous_run) do
    create(
      :run,
      :halted,
      pipeline: pipeline,
      pipeline_klass: klass
    )
  end

  before do
    previous_run
  end

  it "creates a new pipeline run from the previous run" do
    expect do
      pipeline.revive!
    end.to change(Ductwork::Run, :count).by(1)

    run = pipeline.current_run
    expect(run).to be_in_progress
    expect(run.triggered_at).to be_almost_now
    expect(run.started_at).to be_almost_now
    expect(run.definition).to eq(previous_run.definition)
    expect(run.definition_sha1).to eq(previous_run.definition_sha1)
    expect(run.pipeline).to eq(pipeline)
    expect(run.pipeline_klass).to eq(pipeline.klass)
  end

  it "duplicates all previously succeeded branches" do
    _completed_branch = create(:branch, :completed, run: previous_run)
    _advancing_branch = create(:branch, :advancing, run: previous_run)

    expect do
      pipeline.revive!
    end.to change(Ductwork::Branch, :count).by(2)

    first_branch, second_branch = pipeline.current_run.branches
    expect(first_branch.started_at).to be_almost_now
    expect(first_branch.completed_at).to be_almost_now
    expect(second_branch.started_at).to be_almost_now
    expect(second_branch.completed_at).to be_almost_now
  end

  it "duplicates all the previously succeeded steps" do
    branch = create(:branch, :completed, run: previous_run)
    completed_step = create(:step, :completed, run: previous_run, branch: branch)
    advancing_step = create(:step, :advancing, run: previous_run, branch: branch)

    expect do
      pipeline.revive!
    end.to change(Ductwork::Step, :count).by(2)

    first_step, second_step = pipeline.current_run.steps
    expect(first_step.started_at).to be_almost_now
    expect(first_step.completed_at).to be_almost_now
    expect(first_step.source_step).to be_in([completed_step, advancing_step])
    expect(second_step.started_at).to be_almost_now
    expect(second_step.completed_at).to be_almost_now
    expect(second_step.source_step).to be_in([completed_step, advancing_step])
  end

  it "duplicates any halted branches as in_progress" do
    halted_branch = create(:branch, :halted, run: previous_run)
    step = create(:step, :completed, run: previous_run, branch: halted_branch)
    create(:job, step:)

    expect do
      pipeline.revive!
    end.to change(Ductwork::Branch, :count).by(1)

    branch = pipeline.current_run.branches.sole
    expect(branch).to be_in_progress
    expect(branch.started_at).to be_almost_now
    expect(branch.completed_at).to be_nil
    expect(branch.last_advanced_at).to be_almost_now
  end

  it "duplicates prior completed steps on a halted branch as completed" do
    halted_branch = create(:branch, :halted, run: previous_run)
    earlier_step = create(
      :step,
      :completed,
      run: previous_run,
      branch: halted_branch,
      started_at: 2.minutes.ago
    )
    latest_step = create(
      :step,
      :completed,
      run: previous_run,
      branch: halted_branch,
      started_at: 1.minute.ago
    )
    create(:job, step: latest_step)

    pipeline.revive!

    revived = pipeline.current_run.steps.find_by(source_step: earlier_step)
    expect(revived).to be_completed
    expect(revived.started_at).to be_almost_now
    expect(revived.completed_at).to be_almost_now
  end

  context "when the halt reason is `job_retries_exhausted`" do
    let(:halted_branch) do
      create(
        :branch,
        :halted,
        run: previous_run,
        halt_reason: "job_retries_exhausted"
      )
    end
    let(:failed_step) { create(:step, :failed, run: previous_run, branch: halted_branch) }
    let(:failed_job) { create(:job, step: failed_step) }

    before do
      failed_job
    end

    it "re-creates the failed step as in_progress" do
      expect do
        pipeline.revive!
      end.to change(Ductwork::Step, :count).by(1)

      step = pipeline.current_run.steps.sole
      expect(step).to be_in_progress
      expect(step.klass).to eq(failed_step.klass)
      expect(step.node).to eq(failed_step.node)
      expect(step.to_transition).to eq(failed_step.to_transition)
      expect(step.source_step).to eq(failed_step)
      expect(step.started_at).to be_almost_now
      expect(step.completed_at).to be_nil
    end

    it "re-enqueues a job preserving the original input_args" do
      expect do
        pipeline.revive!
      end.to change(Ductwork::Job, :count).by(1)

      job = pipeline.current_run.steps.sole.job
      expect(job.klass).to eq(failed_step.klass)
      expect(job.input_args).to eq(failed_job.input_args)
    end
  end

  context "when the halt reason is an advancer halt" do
    let(:halted_branch) do
      create(
        :branch,
        :halted,
        run: previous_run,
        halt_reason: "advancer_retries_exhausted"
      )
    end
    let(:completed_step) do
      create(:step, :completed, run: previous_run, branch: halted_branch)
    end
    let(:completed_job) do
      create(
        :job,
        step: completed_step,
        klass: completed_step.klass,
        output_payload: JSON.dump({ payload: 42 })
      )
    end

    before do
      completed_job
    end

    it "re-creates the latest step as :advancing" do
      expect do
        pipeline.revive!
      end.to change(Ductwork::Step, :count).by(1)

      step = pipeline.current_run.steps.sole
      expect(step).to be_advancing
      expect(step.klass).to eq(completed_step.klass)
      expect(step.node).to eq(completed_step.node)
      expect(step.to_transition).to eq(completed_step.to_transition)
      expect(step.source_step).to eq(completed_step)
      expect(step.started_at).to be_almost_now
    end

    it "duplicates the job preserving the original output_payload" do
      expect do
        pipeline.revive!
      end.to change(Ductwork::Job, :count).by(1)

      job = pipeline.current_run.steps.sole.job
      expect(job.klass).to eq(completed_step.klass)
      expect(job.output_payload).to eq(completed_job.output_payload)
      expect(job.started_at).to be_almost_now
      expect(job.completed_at).to be_almost_now
    end

    it "produces a branch the advancer can claim" do
      Ductwork::Process.adopt_or_create_current!
      pipeline.revive!

      expected = pipeline.current_run.branches.sole
      claimed = Ductwork::BranchClaim.new(klass).latest

      expect(claimed).to eq(expected)
    end
  end

  it "does not duplicate the context by default" do
    create(:tuple, run: previous_run)
    create(:tuple, run: previous_run)

    expect do
      pipeline.revive!
    end.not_to change(Ductwork::Tuple, :count)
  end

  it "duplicates the context when passed the argument" do
    create(:tuple, run: previous_run)
    create(:tuple, run: previous_run)

    expect do
      pipeline.revive!(duplicate_context: true)
    end.to change(Ductwork::Tuple, :count).by(2)

    first_tuple, second_tuple = pipeline.current_run.tuples
    expect(first_tuple.first_set_at).to be_almost_now
    expect(first_tuple.last_set_at).to be_almost_now
    expect(second_tuple.first_set_at).to be_almost_now
    expect(second_tuple.last_set_at).to be_almost_now
  end

  it "sets the pipeline status and returns the pipelien" do
    returned_pipeline = nil

    expect do
      returned_pipeline = pipeline.revive!(duplicate_context: true)
    end.to change(pipeline, :status).from("halted").to("in_progress")
    expect(returned_pipeline).to eq(pipeline)
  end

  # NOTE: this case is purely defensive
  context "when there is no previous run" do
    before do
      previous_run.destroy!
    end

    it "raises an error" do
      expect do
        pipeline.revive!
      end.to raise_error(
        described_class::ReviveError,
        "Cannot revive pipeline without previous run"
      )
    end
  end

  context "when the pipeline is not halted" do
    subject(:pipeline) { create(:pipeline, :completed) }

    it "raises an error" do
      expect do
        pipeline.revive!
      end.to raise_error(
        described_class::ReviveError,
        "Cannot revive #{pipeline.status} pipeline"
      )
    end
  end
end
