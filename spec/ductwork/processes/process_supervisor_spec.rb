# frozen_string_literal: true

RSpec.describe Ductwork::Processes::ProcessSupervisor do
  let(:supervisor) { described_class.new }
  let(:block) { ->(_supervisor) {} }
  let(:running_supervisors) { [] }

  after do
    running_supervisors.each do |running_supervisor, thread|
      running_supervisor.send(:running_context).shutdown!
      next if thread.join(Helpers::WORKER_SHUTDOWN_BUDGET)

      thread.kill
      running_supervisor.shutdown
    end

    supervisor.workers.each do |worker|
      ::Process.kill(:KILL, worker[:pid])
    end
  end

  describe "#initialize" do
    it "calls the supervisor start lifecycle hooks" do
      allow(block).to receive(:call).and_call_original
      Ductwork.on_supervisor_start(&block)

      supervisor = described_class.new

      expect(block).to have_received(:call).with(supervisor)
    end
  end

  describe "#add_worker" do
    it "starts new workers" do
      supervisor.add_worker { sleep }
      supervisor.add_worker { sleep }

      expect(supervisor.workers.count).to eq(2)
      supervisor.workers.each do |worker|
        status = ::Process.kill(0, worker[:pid])
        expect(status).to eq(1)
      end
    end
  end

  describe "#run" do
    it "monitors and restarts workers when they crash" do
      run_in_thread(supervisor)

      supervisor.add_worker { raise "simulating a crash" }

      sleep(0.5) # Wait for process to be restarted (squishy)

      status = ::Process.kill(0, supervisor.workers.first[:pid])
      expect(supervisor.workers.count).to eq(1)
      expect(status).to eq(1)
    end

    it "keeps its own process record's heartbeat fresh", :no_transaction do
      Ductwork.configuration.supervisor_polling_timeout = 0.1
      run_in_thread(supervisor)

      adopted_at = wait_for do
        Ductwork::Process.current&.last_heartbeat_at
      end
      refreshed_at = wait_for do
        latest = Ductwork::Process.current&.last_heartbeat_at
        latest if latest && latest > adopted_at
      end

      expect(refreshed_at).to be > adopted_at
    end
  end

  describe "#shutdown" do
    it "gracefully terminates all workers" do
      supervisor.add_worker do
        Signal.trap(:TERM) { exit(0) }
        sleep
      end
      supervisor.add_worker do
        Signal.trap(:TERM) { exit(0) }
        sleep
      end
      pids = supervisor.workers.map { |worker| worker[:pid] }

      sleep(0.5)
      supervisor.shutdown

      expect(supervisor.workers.count).to eq(0)
      pids.each do |pid|
        expect do
          ::Process.kill(0, pid)
        end.to raise_error(Errno::ESRCH, "No such process")
      end
    end

    it "waits then forcefully terminates remaining workers" do
      Ductwork.configuration.supervisor_shutdown_timeout = 1

      supervisor = described_class.new
      supervisor.add_worker { sleep }
      supervisor.add_worker { sleep }
      pids = supervisor.workers.map { |worker| worker[:pid] }

      supervisor.shutdown
      sleep(1.1) # Wait for timeout

      expect(supervisor.workers.count).to eq(0)
      pids.each do |pid|
        expect do
          ::Process.kill(0, pid)
        end.to raise_error(Errno::ESRCH, "No such process")
      end
    end

    it "reaps its own process record" do
      Ductwork::Process.adopt_or_create_current!(:supervisor)

      supervisor.shutdown

      expect(Ductwork::Process.current).to be_nil
    end

    it "calls the supervisor stop lifecycle hooks" do
      allow(block).to receive(:call).and_call_original
      Ductwork.on_supervisor_stop(&block)
      supervisor = described_class.new

      supervisor.shutdown

      expect(block).to have_received(:call).with(supervisor)
    end
  end

  def run_in_thread(supervisor)
    Thread.new { supervisor.run }.tap do |thread|
      thread.name = "ductwork.spec.process_supervisor"
      running_supervisors << [supervisor, thread]
    end
  end
end
