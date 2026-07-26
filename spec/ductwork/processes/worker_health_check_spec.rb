# frozen_string_literal: true

RSpec.describe Ductwork::Processes::WorkerHealthCheck do
  describe "#check" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    subject(:worker_health_check) do
      described_class.new(workers, role)
    end

    let(:role) { :thread_supervisor }
    let(:dead_job_worker) do
      instance_double(
        Ductwork::Processes::JobWorker,
        alive?: false,
        restart: nil,
        pipeline: pipeline.klass,
        execution: execution,
        name: "dead"
      )
    end
    let(:stuck_job_worker) do
      instance_double(
        Ductwork::Processes::JobWorker,
        stuck?: true,
        kill: nil,
        join: nil,
        restart: nil,
        pipeline: pipeline.klass,
        execution: execution,
        name: "stuck"
      ).tap do |worker|
        allow(worker).to receive(:alive?).and_return(true, true, false)
      end
    end
    let(:unkillable_job_worker) do
      instance_double(
        Ductwork::Processes::JobWorker,
        alive?: true,
        stuck?: true,
        kill: nil,
        join: nil,
        restart: nil,
        pipeline: pipeline.klass,
        execution: execution,
        name: "unkillable"
      )
    end
    let(:healthy_job_worker) do
      instance_double(
        Ductwork::Processes::JobWorker,
        alive?: true,
        execution: execution,
        stuck?: false
      )
    end
    let(:dead_pipeline_advancer) do
      instance_double(
        Ductwork::Processes::PipelineAdvancer,
        is_a?: true,
        alive?: false,
        restart: nil,
        branch: branch,
        name: "dead"
      )
    end
    let(:stuck_pipeline_advancer) do
      instance_double(
        Ductwork::Processes::PipelineAdvancer,
        is_a?: true,
        stuck?: true,
        kill: nil,
        join: nil,
        restart: nil,
        branch: branch,
        name: "stuck"
      ).tap do |advancer|
        allow(advancer).to receive(:alive?).and_return(true, true, false)
      end
    end
    let(:workers) do
      [
        healthy_job_worker,
        dead_job_worker,
        stuck_job_worker,
        healthy_job_worker,
        dead_pipeline_advancer,
        stuck_pipeline_advancer,
      ]
    end
    let(:execution) { create(:execution, job:) }
    let(:job) { create(:job) }
    let(:branch) { build_stubbed(:branch) }
    let(:run) { job.step.run }
    let(:pipeline) { run.pipeline }

    before do
      allow(Ductwork.logger).to receive(:warn).and_call_original
      run.in_progress!
      pipeline.in_progress!
    end

    it "restarts dead workers" do
      worker_health_check.check

      expect(dead_job_worker).to have_received(:restart)
      expect(dead_pipeline_advancer).to have_received(:restart)
    end

    it "logs dead workers" do
      worker_health_check.check

      expect(Ductwork.logger).to have_received(:warn).with(
        msg: "Restarted dead thread",
        role: role,
        thread: "dead",
        job_id: job.id
      )
      expect(Ductwork.logger).to have_received(:warn).with(
        msg: "Restarted dead thread",
        role: role,
        thread: "dead",
        branch_id: branch.id
      )
    end

    it "kills and restarts stuck workers" do
      worker_health_check.check

      expect(stuck_job_worker).to have_received(:kill)
      expect(stuck_job_worker).to have_received(:join).with(1)
      expect(stuck_job_worker).to have_received(:restart)

      expect(stuck_pipeline_advancer).to have_received(:kill)
      expect(stuck_pipeline_advancer).to have_received(:join).with(1)
      expect(stuck_pipeline_advancer).to have_received(:restart)
    end

    it "logs stuck workers" do
      worker_health_check.check

      expect(Ductwork.logger).to have_received(:warn).with(
        msg: "Killed and restarted stuck thread",
        role: role,
        thread: "stuck"
      ).twice
    end

    context "when a stuck worker cannot be confirmed dead" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:workers) { [unkillable_job_worker] }

      before do
        stub_const("#{described_class}::KILL_BUDGET", 0.2)
        stub_const("#{described_class}::JOIN_TIMEOUT", 0.05)
      end

      it "does not start a replacement thread" do
        worker_health_check.check

        expect(unkillable_job_worker).to have_received(:kill).at_least(:once)
        expect(unkillable_job_worker).not_to have_received(:restart)
      end

      it "logs the deferral" do
        worker_health_check.check

        expect(Ductwork.logger).to have_received(:warn).with(
          msg: "Unable to confirm stuck thread died, deferring restart",
          role: role,
          thread: "unkillable"
        )
      end

      it "retries the kill on the next check" do
        worker_health_check.check
        worker_health_check.check

        expect(unkillable_job_worker).to have_received(:restart).exactly(0).times
        expect(unkillable_job_worker).to have_received(:kill).at_least(:twice)
      end
    end
  end
end
