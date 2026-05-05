# frozen_string_literal: true

RSpec.describe Ductwork::Availability do
  describe "validations" do
    let(:started_at) { Time.current }
    let(:pipeline_klass) { "MyPipeline" }

    it "is invalid when started_at is blank" do
      availability = described_class.new(pipeline_klass:)

      expect(availability).not_to be_valid
      expect(availability.errors.full_messages.sole).to eq("Started at can't be blank")
    end

    it "is invalid when the pipeline klass is blank" do
      availability = described_class.new(started_at:)

      expect(availability).not_to be_valid
      expect(availability.errors.full_messages.sole).to eq("Pipeline klass can't be blank")
    end

    it "is valid otherwise" do
      availability = described_class.new(pipeline_klass:, started_at:)

      expect(availability).to be_valid
    end
  end

  describe "#abandon!" do
    subject(:availability) do
      described_class.create!(
        execution:,
        pipeline_klass:,
        started_at:
      )
    end

    let(:execution) { create(:execution) }
    let(:pipeline_klass) { "MyPipeline" }
    let(:started_at) { Time.current }

    it "no-ops if the execution is completed" do
      execution.update!(completed_at: Time.current)

      expect do
        availability.abandon!
      end.to not_change(execution.job.executions, :count)
    end

    it "is idempotent" do
      availability.abandon!

      expect do
        availability.abandon!
      end.to not_change(execution.job.executions, :count)
    end

    it "crashes the execution" do
      allow(execution).to receive(:crashed!)
      allow(availability).to receive(:execution).and_return(execution) # rubocop:disable RSpec/SubjectStub

      availability.abandon!

      expect(execution).to have_received(:crashed!)
    end
  end
end
