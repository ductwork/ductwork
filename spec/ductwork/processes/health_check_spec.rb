# frozen_string_literal: true

RSpec.describe Ductwork::Processes::HealthCheck do
  describe "#run" do
    context "when given no pid option" do
      let(:process1) { create(:process, :supervisor, last_heartbeat_at: 1.hour.ago) }
      let(:process2) { create(:process, :supervisor, last_heartbeat_at: 1.second.ago) }

      it "reports the health of all top-level parent processes simply" do
        process1
        process2

        expect do
          expect do
            described_class.new.run
          end.to raise_error(SystemExit)
        end.to output(<<~STDOUT).to_stdout
          unhealthy
          healthy
        STDOUT
      end

      it "reports the health of all top-level parent processes verbosely" do
        process1
        process2

        expect do
          expect do
            described_class.new(verbose: true).run
          end.to raise_error(SystemExit)
        end.to output(<<~STDOUT).to_stdout
          PID #{process1.pid} (#{process1.machine_identifier})
            ID: #{process1.id}
            Created At: #{process1.created_at.iso8601}
            Last Heartbeat At: #{process1.last_heartbeat_at.iso8601}
            Status: unhealthy
          PID #{process2.pid} (#{process2.machine_identifier})
            ID: #{process2.id}
            Created At: #{process2.created_at.iso8601}
            Last Heartbeat At: #{process2.last_heartbeat_at.iso8601}
            Status: healthy
        STDOUT
      end

      it "returns a zero exit code for all healthy processes" do
        process2
        create(:process, last_heartbeat_at: 20.seconds.ago)

        exit_code = capture_exit_code { described_class.new.run }

        expect(exit_code).to eq(0)
      end

      it "returns a non-zero exit code for any unhealthy process" do
        process1
        process2

        exit_code = capture_exit_code { described_class.new.run }

        expect(exit_code).to eq(1)
      end
    end

    context "when the process is healthy" do
      subject(:health_check) { described_class.new(pid: process.pid) }

      let(:process) do
        create(:process, :current, :supervisor, last_heartbeat_at: 1.second.ago)
      end

      it "reports healthy" do
        expect do
          expect do
            health_check.run
          end.to raise_error(SystemExit)
        end.to output("healthy\n").to_stdout
      end

      it "exits with a zero exit code" do
        exit_code = capture_exit_code { health_check.run }

        expect(exit_code).to be_zero
      end

      context "when given the 'verbose' option" do
        subject(:health_check) { described_class.new(pid: process.pid, verbose: true) }

        it "prints a full report of the process record" do
          expect do
            expect do
              health_check.run
            end.to raise_error(SystemExit)
          end.to output(<<~STDOUT).to_stdout
            PID #{process.pid} (#{process.machine_identifier})
              ID: #{process.id}
              Created At: #{process.created_at.iso8601}
              Last Heartbeat At: #{process.last_heartbeat_at.iso8601}
              Status: healthy
          STDOUT
        end
      end
    end

    context "when the process is not healthy" do
      subject(:health_check) { described_class.new(pid: process.pid) }

      let(:process) do
        create(:process, :current, :supervisor, last_heartbeat_at: 1.hour.ago)
      end

      it "reports unhealthy" do
        expect do
          expect do
            health_check.run
          end.to raise_error(SystemExit)
        end.to output("unhealthy\n").to_stdout
      end

      it "exits with a non-zero exit code" do
        exit_code = capture_exit_code { health_check.run }

        expect(exit_code).to eq(1)
      end

      context "when given the 'verbose' option" do
        subject(:health_check) { described_class.new(pid: process.pid, verbose: true) }

        it "prints a full report of the process record" do
          expect do
            expect do
              health_check.run
            end.to raise_error(SystemExit)
          end.to output(<<~STDOUT).to_stdout
            PID #{process.pid} (#{process.machine_identifier})
              ID: #{process.id}
              Created At: #{process.created_at.iso8601}
              Last Heartbeat At: #{process.last_heartbeat_at.iso8601}
              Status: unhealthy
          STDOUT
        end
      end
    end

    context "when the process is missing" do
      it "reports not running" do
        expect do
          expect do
            described_class.run(pid: 1)
          end.to raise_error(SystemExit)
        end.to output("dead\n").to_stdout
      end

      it "exits with a non-zero exit code" do
        exit_code = capture_exit_code { described_class.run(pid: 1) }

        expect(exit_code).to eq(1)
      end

      context "when given the 'verbose' option" do
        subject(:health_check) { described_class.new(pid: 123, verbose: true) }

        let(:machine_identifier) { Ductwork::MachineIdentifier.fetch }

        it "prints a full report of the process record" do
          expect do
            expect do
              health_check.run
            end.to raise_error(SystemExit)
          end.to output(<<~STDOUT).to_stdout
            PID 123 (#{machine_identifier})
              Status: dead
          STDOUT
        end
      end
    end

    def capture_exit_code(&block)
      block.call

      raise "Expected SystemExit but nothing was raised"
    rescue SystemExit => e
      e.status
    end
  end
end
