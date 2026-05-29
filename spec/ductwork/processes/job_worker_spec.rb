# frozen_string_literal: true

RSpec.describe Ductwork::Processes::JobWorker do
  let(:pipeline) { "MyPipeline" }
  let(:id) { rand(1..5) }

  before do
    Ductwork.configuration.job_worker_polling_timeout = 0.1
  end

  describe "#start", :not_transaction do
    before do
      create(:process, :current)
    end

    it "creates a thread" do
      job_worker = described_class.new(pipeline, id)

      expect do
        job_worker.start
      end.to change(job_worker, :thread).from(nil).to(be_a(Thread))
      expect(job_worker.thread).to be_alive
      expect(job_worker.thread.name).to eq("ductwork.job_worker.#{pipeline}.#{id}")

      shutdown(job_worker)
    end

    it "updates the last heartbeat timestamp" do
      be_now = be_within(1.second).of(Time.current)
      job_worker = described_class.new(pipeline, id)

      expect(job_worker.last_heartbeat_at).to be_now

      job_worker.start
      sleep(1)

      expect(job_worker.thread).to be_alive
      expect(job_worker.last_heartbeat_at).to be_now

      shutdown(job_worker)
    end
  end

  describe "#restart", :not_transaction do
    subject(:job_worker) { described_class.new(pipeline, id) }

    let(:execution) { create(:execution) }

    it "cleans up claimed resources from a thread crash" do
      allow(execution).to receive(:crashed!)
      job_worker.instance_variable_set(:@execution, execution)

      job_worker.restart

      expect(execution).to have_received(:crashed!)
      expect(job_worker.execution).to be_nil

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

    it "returns false if the thread is null" do
      job_worker = described_class.new(pipeline, id)

      expect(job_worker).not_to be_alive
    end
  end

  describe "#stuck?" do
    subject(:job_worker) { described_class.new(pipeline, id) }

    it "returns false if an execution is claimed" do
      execution = build(:execution)

      job_worker.instance_variable_set(:@execution, execution)

      expect(job_worker).not_to be_stuck
    end

    it "returns false if the last heartbeat was within the threshold" do
      job_worker.instance_variable_set(:@last_heartbeat_at, 30.seconds.ago)

      expect(job_worker).not_to be_stuck
    end

    it "returns true otherwise" do
      job_worker.instance_variable_set(:@execution, nil)
      job_worker.instance_variable_set(:@last_heartbeat_at, 7.minutes.ago)

      expect(job_worker).to be_stuck
    end
  end

  describe "#stop" do
    it "informs execution to exit the main work loop" do
      job_worker = described_class.new(pipeline, id)
      job_worker.start

      job_worker.stop
      sleep(0.1)

      expect(job_worker).not_to be_alive
    end
  end

  describe "#kill" do
    it "delegates to the thread" do
      job_worker = described_class.new(pipeline, id)
      job_worker.start

      job_worker.kill
      sleep(0.1)

      expect(job_worker).not_to be_alive
    end
  end

  describe "#name" do
    it "returns the thread name" do
      job_worker = described_class.new(pipeline, id)

      expect(job_worker.name).to eq("ductwork.job_worker.#{pipeline}.#{id}")
    end
  end

  def shutdown(job_worker)
    job_worker.stop
    sleep(0.1)
    job_worker.thread&.kill
  end
end
