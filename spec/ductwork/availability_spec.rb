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

    it "locks the execution" do
      execution = instance_double(
        Ductwork::Execution,
        job: spy,
        lock!: nil,
        reload: nil,
        completed_at: Time.current
      )

      # rubocop:disable RSpec/SubjectStub
      allow(availability).to receive(:execution).and_return(execution)
      # rubocop:enable RSpec/SubjectStub

      availability.abandon!

      expect(execution).to have_received(:lock!)
    end

    it "no-ops if the execution is completed" do
      execution.update!(completed_at: Time.current)

      expect do
        availability.abandon!
      end.to not_change(execution.job.executions, :count)
    end

    it "crashes the execution" do
      job = instance_double(Ductwork::Job, execution_crashed!: nil)
      allow(execution).to receive(:job).and_return(job)

      availability.abandon!

      expect(execution.job).to have_received(:execution_crashed!).with(execution)
    end
  end
end
