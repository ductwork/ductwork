# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline, "#revive!" do
  subject(:pipeline) { create(:pipeline, :halted, klass:) }

  let(:klass) { "MyPipeline" }
  let(:previous_run) { create(:run, :halted, pipeline: pipeline, pipeline_klass: klass) }

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

  it "duplicates any failed branches" do
    _halted_branch = create(:branch, :halted, run: previous_run)

    expect do
      pipeline.revive!
    end.to change(Ductwork::Branch, :count).by(1)

    branch = pipeline.current_run.branches.sole
    expect(branch).to be_in_progress
    expect(branch.started_at).to be_almost_now
    expect(branch.completed_at).to be_nil
    expect(branch.last_advanced_at).to be_almost_now
  end

  it "duplicates any succeeded steps on halted branches" do
    branch = create(:branch, :halted, run: previous_run)
    completed_step = create(:step, :completed, run: previous_run, branch: branch)

    expect do
      pipeline.revive!
    end.to change(Ductwork::Step, :count).by(1)

    step = pipeline.current_run.steps.sole
    expect(step).to be_completed
    expect(step.source_step).to eq(completed_step)
    expect(step.started_at).to be_almost_now
    expect(step.completed_at).to be_almost_now
  end

  it "re-creates the failed step and job on the halted branch" do
    branch = create(:branch, :halted, run: previous_run)
    failed_step = create(:step, :failed, run: previous_run, branch: branch)

    expect do
      pipeline.revive!
    end.to change(Ductwork::Step, :count).by(1)
      .and change(Ductwork::Job, :count).by(1)

    step = pipeline.current_run.steps.sole
    expect(step).to be_in_progress
    expect(step.klass).to eq(failed_step.klass)
    expect(step.node).to eq(failed_step.node)
    expect(step.to_transition).to eq(failed_step.to_transition)
    expect(step.started_at).to be_almost_now
    expect(step.completed_at).to be_nil
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
