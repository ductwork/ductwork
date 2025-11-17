# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline do
  describe "#advance!" do
    subject(:pipeline) do
      create(:pipeline, status: :in_progress, definition: definition)
    end

    let(:definition) { {}.to_json }

    it "completes steps in 'advancing' status" do
      advancing_step = create(:step, status: :advancing, pipeline: pipeline)
      in_progress_step = create(:step, status: :in_progress, pipeline: pipeline)

      expect do
        pipeline.advance!
      end.to change { advancing_step.reload.status }.to("completed")
        .and(change { advancing_step.completed_at }.from(nil))
        .and(not_change { in_progress_step.reload.status })
    end

    it "only updates steps for the configured pipelines" do
      other_pipeline = create(:pipeline, klass: "OtherPipeline")
      skipped_step = create(:step, status: :advancing, pipeline: other_pipeline)

      expect do
        pipeline.advance!
      end.not_to(change { skipped_step.reload.status })
    end

    it "does not mark the pipeline as complete if some steps not completed" do
      create(:step, status: :in_progress, pipeline: pipeline)

      expect do
        pipeline.advance!
      end.not_to(change { pipeline.reload.status })
    end

    it "marks the pipeline as complete if all steps are completed" do
      create(:step, status: :advancing, pipeline: pipeline)

      expect do
        pipeline.advance!
      end.to change { pipeline.reload.status }.from("in_progress").to("completed")
    end
  end
end
