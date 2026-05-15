# frozen_string_literal: true

RSpec.describe Ductwork::Processes::PipelineAdvancer do
  let(:klass) { "MyPipeline" }

  before do
    Ductwork.configuration.pipeline_polling_timeout = 0.1
  end

  describe "#start" do
    it "creates a thread" do
      pipeline_advancer = described_class.new(klass)

      expect do
        pipeline_advancer.start
      end.to change(pipeline_advancer, :thread).from(nil).to(be_a(Thread))
      expect(pipeline_advancer.thread).to be_alive
      expect(pipeline_advancer.thread.name).to eq("ductwork.pipeline_advancer.#{klass}.0")

      shutdown(pipeline_advancer)
    end

    it "updates the last heartbet timestamp" do
      be_now = be_within(1.second).of(Time.current)
      pipeline_advancer = described_class.new(klass)

      expect(pipeline_advancer.last_heartbeat_at).to be_now

      pipeline_advancer.start
      sleep(1)

      expect(pipeline_advancer.last_heartbeat_at).to be_now

      shutdown(pipeline_advancer)
    end
  end

  describe "#restart" do
    subject(:pipeline_advancer) { described_class.new(klass) }

    let(:branch) { create(:branch, :claimed) }
    let(:transition) { create(:transition, branch:) }
    let(:advancement) { create(:advancement, transition:) }

    before do
      advancement
    end

    it "cleans up claimed resources from a thread crash" do
      pipeline_advancer.instance_variable_set(:@branch, branch)

      expect do
        pipeline_advancer.restart
      end.to change { branch.reload.claimed_for_advancing_at }.to(nil)
        .and change { advancement.reload.completed_at }.to(be_almost_now)
        .and change(advancement, :error_klass).to("Ductwork::ThreadCrash")
        .and change(advancement, :error_message).to(
          "Advancement abandoned from a thread crash"
        )
      expect(pipeline_advancer.branch).to be_nil

      shutdown(pipeline_advancer)
    end
  end

  describe "#alive?" do
    it "returns true when the thread is alive" do
      pipeline_advancer = described_class.new(klass)
      pipeline_advancer.start

      expect(pipeline_advancer).to be_alive

      shutdown(pipeline_advancer)
    end

    it "returns false if the thread is dead" do
      pipeline_advancer = described_class.new(klass)
      pipeline_advancer.start
      pipeline_advancer.kill
      sleep(0.1)

      expect(pipeline_advancer).not_to be_alive

      shutdown(pipeline_advancer)
    end

    it "returns false when the thread is nil" do
      pipeline_advancer = described_class.new(klass)

      expect(pipeline_advancer).not_to be_alive
    end
  end

  describe "#stop" do
    it "informs execution to exit the main work loop" do
      pipeline_advancer = described_class.new(klass)
      pipeline_advancer.start

      pipeline_advancer.stop
      sleep(0.1)

      expect(pipeline_advancer).not_to be_alive
    end
  end

  describe "#kill" do
    it "delegates to the thread" do
      pipeline_advancer = described_class.new(klass)
      pipeline_advancer.start

      pipeline_advancer.kill
      sleep(0.1)

      expect(pipeline_advancer).not_to be_alive
    end
  end

  describe "#name" do
    it "returns the name" do
      pipeline_advancer = described_class.new(klass)

      expect(pipeline_advancer.name).to eq("ductwork.pipeline_advancer.#{klass}.0")
    end

    it "returns the name with the optional index" do
      pipeline_advancer = described_class.new(klass, 42)

      expect(pipeline_advancer.name).to eq("ductwork.pipeline_advancer.#{klass}.42")
    end
  end

  def shutdown(pipeline_advancer)
    pipeline_advancer.stop
    sleep(0.1)
    pipeline_advancer.kill
  end
end
