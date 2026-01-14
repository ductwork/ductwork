# frozen_string_literal: true

RSpec.describe Ductwork::Processes::JobWorker do
  let(:pipeline) { "MyPipeline" }
  let(:id) { rand(1..5) }

  before do
    Ductwork.configuration.job_worker_polling_timeout = 0.1
  end

  describe "#start" do
    it "creates a thread" do
      job_worker = described_class.new(pipeline, id)

      expect do
        job_worker.start
      end.to change(job_worker, :thread).from(nil).to(be_a(Thread))
      expect(job_worker.thread).to be_alive
      expect(job_worker.thread.name).to eq("ductwork.job_worker.#{id}")

      shutdown(job_worker)
    end

    it "updates the last heartbeat timestamp" do
      be_now = be_within(1.second).of(Time.current)
      job_worker = described_class.new(pipeline, id)

      expect(job_worker.last_heartbeat_at).to be_now

      job_worker.start
      sleep(1)

      expect(job_worker.last_heartbeat_at).to be_now

      shutdown(job_worker)
    end
  end

  describe "#alive?" do
    it "returns true when the thread is alive" do
      job_worker = described_class.new(pipeline, id)
      job_worker.start

      expect(job_worker).to be_alive

      shutdown(job_worker)
    end

    it "returns false if the thread is dead" do
      job_worker = described_class.new(pipeline, id)
      job_worker.start

      job_worker.thread.kill
      sleep(0.1)

      expect(job_worker).not_to be_alive
    end

    it "returns false if the thread is nul" do
      job_worker = described_class.new(pipeline, id)

      expect(job_worker).not_to be_alive
    end
  end

  describe "#stop" do
    it "informs execution to exit the main work loop" do
      job_worker = described_class.new(pipeline, id)
      job_worker.start

      job_worker.stop
      sleep(0.1)

      expect(job_worker.thread).not_to be_alive
    end
  end

  describe "#name" do
    it "returns the thread name" do
      job_worker = described_class.new(pipeline, id)

      expect(job_worker.name).to eq("ductwork.job_worker.#{id}")
    end
  end

  describe "#kill" do
    it "delegates to the thread" do
      job_worker = described_class.new(pipeline, id)
      job_worker.start

      job_worker.kill

      expect(job_worker).not_to be_alive
    end
  end

  def shutdown(job_worker)
    job_worker.stop
    sleep(0.1)
    job_worker.thread&.kill
  end
end
