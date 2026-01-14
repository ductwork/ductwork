# frozen_string_literal: true

RSpec.describe Ductwork::Processes::ProcessSupervisor do
  let(:supervisor) { described_class.new }
  let(:block) { ->(_supervisor) {} }

  after do
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
      thread = Thread.new { supervisor.run }

      supervisor.add_worker { raise "simulating a crash" }

      sleep(0.5) # Wait for process to be restarted

      status = ::Process.kill(0, supervisor.workers.first[:pid])
      expect(supervisor.workers.count).to eq(1)
      expect(status).to eq(1)

      supervisor.shutdown
      thread.join
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

    it "calls the supervisor stop lifecycle hooks" do
      allow(block).to receive(:call).and_call_original
      Ductwork.on_supervisor_stop(&block)
      supervisor = described_class.new

      supervisor.shutdown

      expect(block).to have_received(:call).with(supervisor)
    end
  end
end
