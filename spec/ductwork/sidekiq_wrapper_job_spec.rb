# frozen_string_literal: true

RSpec.describe Ductwork::SidekiqWrapperJob do
  describe "#perform" do
    let(:klass) { "MyFirstJob" }
    let(:args) { [1, "a"] }
    let(:jid) { SecureRandom.uuid }
    let!(:job_record) do
      pipeline = Ductwork::Pipeline.create!(
        name: "MyPipeline",
        status: "in_progress",
        triggered_at: Time.current
      )
      step = Ductwork::Step.create!(
        status: "in_progress",
        step_type: "start",
        klass:,
        pipeline:
      )

      Ductwork::Job.create!(
        adapter: "sidekiq",
        enqueued_at: Time.current,
        status: "running",
        step:,
        jid:
      )
    end

    it "calls the target class" do
      instance = instance_double(MyFirstJob, perform: "return_value")
      allow(MyFirstJob).to receive(:new).and_return(instance)

      job = described_class.new
      job.jid = jid
      job.perform(klass, *args)

      expect(MyFirstJob).to have_received(:new)
      expect(instance).to have_received(:perform).with(*args)
    end

    it "stores the return value and completes the job" do
      job = described_class.new
      job.jid = jid
      job.perform(klass, *args)

      expect(job_record.reload).to be_advancing
      expect(job_record.advancing_at).to be_within(1.second).of(Time.current)
      expect(job_record.return_value).to eq("return_value")
    end
  end
end
