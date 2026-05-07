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

  context "when the previous run had branch links" do
    context "with a divide shape (one parent, many halted children)" do
      let(:parent_branch) { create(:branch, :completed, run: previous_run) }
      let(:child_branch1) { create(:branch, :halted, run: previous_run) }
      let(:child_branch2) { create(:branch, :halted, run: previous_run) }

      before do
        create(:step, :completed, run: previous_run, branch: parent_branch)
        child_step1 = create(:step, :completed, run: previous_run, branch: child_branch1)
        child_step2 = create(:step, :completed, run: previous_run, branch: child_branch2)
        create(:job, step: child_step1)
        create(:job, step: child_step2)
        create(:branch_link, parent_branch: parent_branch, child_branch: child_branch1)
        create(:branch_link, parent_branch: parent_branch, child_branch: child_branch2)
      end

      it "duplicates each branch link" do
        expect do
          pipeline.revive!
        end.to change(Ductwork::BranchLink, :count).by(2)
      end

      it "scopes the new links to branches in the new run" do
        pipeline.revive!

        new_branch_ids = pipeline.current_run.branches.pluck(:id)
        new_links = Ductwork::BranchLink.where(
          parent_branch_id: new_branch_ids,
          child_branch_id: new_branch_ids
        )

        expect(new_links.count).to eq(2)
      end

      it "preserves the topology of the previous run" do
        pipeline.revive!

        old_to_new = map_old_to_new_branch_ids(pipeline.current_run)

        expect(
          Ductwork::BranchLink.exists?(
            parent_branch_id: old_to_new.fetch(parent_branch.id),
            child_branch_id: old_to_new.fetch(child_branch1.id)
          )
        ).to be(true)
        expect(
          Ductwork::BranchLink.exists?(
            parent_branch_id: old_to_new.fetch(parent_branch.id),
            child_branch_id: old_to_new.fetch(child_branch2.id)
          )
        ).to be(true)
      end
    end

    context "with a collapse shape (many parents, one halted child)" do
      let(:parent_branch1) { create(:branch, :completed, run: previous_run) }
      let(:parent_branch2) { create(:branch, :completed, run: previous_run) }
      let(:child_branch) { create(:branch, :halted, run: previous_run) }

      before do
        create(:step, :completed, run: previous_run, branch: parent_branch1)
        create(:step, :completed, run: previous_run, branch: parent_branch2)
        child_step = create(:step, :completed, run: previous_run, branch: child_branch)
        create(:job, step: child_step)
        create(:branch_link, parent_branch: parent_branch1, child_branch: child_branch)
        create(:branch_link, parent_branch: parent_branch2, child_branch: child_branch)
      end

      it "duplicates each branch link" do
        expect do
          pipeline.revive!
        end.to change(Ductwork::BranchLink, :count).by(2)
      end

      it "preserves the topology of the previous run" do
        pipeline.revive!

        old_to_new = map_old_to_new_branch_ids(pipeline.current_run)

        expect(
          Ductwork::BranchLink.exists?(
            parent_branch_id: old_to_new.fetch(parent_branch1.id),
            child_branch_id: old_to_new.fetch(child_branch.id)
          )
        ).to be(true)
        expect(
          Ductwork::BranchLink.exists?(
            parent_branch_id: old_to_new.fetch(parent_branch2.id),
            child_branch_id: old_to_new.fetch(child_branch.id)
          )
        ).to be(true)
      end
    end

    context "with a multi-level divide-then-collapse topology" do
      let(:grandparent) { create(:branch, :completed, run: previous_run) }
      let(:middle1) { create(:branch, :completed, run: previous_run) }
      let(:middle2) { create(:branch, :completed, run: previous_run) }
      let(:grandchild) { create(:branch, :halted, run: previous_run) }

      before do
        create(:step, :completed, run: previous_run, branch: grandparent)
        create(:step, :completed, run: previous_run, branch: middle1)
        create(:step, :completed, run: previous_run, branch: middle2)
        grandchild_step = create(:step, :completed, run: previous_run, branch: grandchild)
        create(:job, step: grandchild_step)

        Ductwork::BranchLink.create!(parent_branch: grandparent, child_branch: middle1)
        Ductwork::BranchLink.create!(parent_branch: grandparent, child_branch: middle2)
        Ductwork::BranchLink.create!(parent_branch: middle1, child_branch: grandchild)
        Ductwork::BranchLink.create!(parent_branch: middle2, child_branch: grandchild)
      end

      it "duplicates every branch link in the topology" do
        expect do
          pipeline.revive!
        end.to change(Ductwork::BranchLink, :count).by(4)
      end

      it "preserves the topology transitively" do
        pipeline.revive!

        old_to_new = map_old_to_new_branch_ids(pipeline.current_run)
        expected_pairs = [
          [grandparent, middle1],
          [grandparent, middle2],
          [middle1, grandchild],
          [middle2, grandchild],
        ]

        expected_pairs.each do |parent, child|
          expect(
            Ductwork::BranchLink.exists?(
              parent_branch_id: old_to_new.fetch(parent.id),
              child_branch_id: old_to_new.fetch(child.id)
            )
          ).to be(true), "expected link from old #{parent.id} -> #{child.id}"
        end
      end
    end

    context "when a branch_link references a branch that was not duplicated" do
      let(:duplicated_branch) { create(:branch, :completed, run: previous_run) }
      let(:undeduplicated_branch) { create(:branch, status: "pending", run: previous_run) }

      before do
        create(:step, :completed, run: previous_run, branch: duplicated_branch)
        Ductwork::BranchLink.create!(
          parent_branch: undeduplicated_branch,
          child_branch: duplicated_branch
        )
      end

      it "raises a KeyError" do
        expect { pipeline.revive! }.to raise_error(KeyError)
      end
    end
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

  def map_old_to_new_branch_ids(new_run)
    new_run.branches.each_with_object({}) do |branch, map|
      sourced = branch.steps.where.not(source_step_id: nil).first
      next if sourced.nil?

      map[sourced.source_step.branch_id] = branch.id
    end
  end
end
