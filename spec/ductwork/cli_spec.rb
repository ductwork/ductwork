# frozen_string_literal: true

RSpec.describe Ductwork::CLI do
  describe ".start!" do
    let(:logger) { instance_double(Logger, :level= => nil, debug?: false) }
    let(:config) do
      instance_double(
        Ductwork::Configuration,
        database: nil,
        logger_level: 0,
        logger_source: "default"
      )
    end

    before do
      ENV.delete("DUCTWORK_ROLE")
      allow(Ductwork::Processes::Launcher).to receive(:start_processes!)
      allow(Ductwork::Processes::HealthCheck).to receive(:run)
      allow(Ductwork::Configuration).to receive(:new).and_return(config)
      allow(Ductwork).to receive(:logger=).and_call_original
      allow(Ductwork).to receive_messages(logger: logger, validate!: true)
    end

    it "loads configuration" do
      described_class.start!([])

      expect(logger).to have_received(:level=).with(0)
      expect(Ductwork).to have_received(:logger=).with(Ductwork::Configuration::DEFAULT_LOGGER)
      expect(Ductwork::Configuration).to have_received(:new).with(role: nil)
    end

    it "loads the role from ENV" do
      ENV["DUCTWORK_ROLE"] = "advancer"

      described_class.start!([])

      expect(Ductwork::Configuration).to have_received(:new).with(role: "advancer")
    end

    context "when given no command" do
      it "calls the process launcher" do
        described_class.start!([])

        expect(Ductwork::Processes::Launcher).to have_received(:start_processes!)
      end

      it "prints the banner" do
        expect do
          described_class.start!([])
        end.to output(<<-BANNER).to_stdout
  \e[1;37m
   \e[0m════════════╗
                ║
                ║
                ║                             ╔═════\e[1;31m●\e[0m
                ║     \e[1;37mD U C T W O R K\e[0m         ║
            ╔═══║═╗                           ║
            ║   ║ ║             ╔═════════╗   ║
     \e[1;37m\e[0m══════╝   ╚═║═══════════════════════║═══╝
                  ╚═════════════╝         ╚═══════════\e[1;37m
  \e[0m
        BANNER
      end
    end

    context "when given the start command" do
      it "calls the process launcher" do
        described_class.start!(["start", "-c", "path/to/config.yml"])

        expect(Ductwork::Processes::Launcher).to have_received(:start_processes!)
      end

      it "prints the banner" do
        expect do
          described_class.start!(["start"])
        end.to output(<<-BANNER).to_stdout
  \e[1;37m
   \e[0m════════════╗
                ║
                ║
                ║                             ╔═════\e[1;31m●\e[0m
                ║     \e[1;37mD U C T W O R K\e[0m         ║
            ╔═══║═╗                           ║
            ║   ║ ║             ╔═════════╗   ║
     \e[1;37m\e[0m══════╝   ╚═║═══════════════════════║═══╝
                  ╚═════════════╝         ╚═══════════\e[1;37m
  \e[0m
        BANNER
      end

      it "validates the steps and pipelines" do
        described_class.start!(["start"])

        expect(Ductwork).to have_received(:validate!)
      end

      context "when a definition fails to load" do
        let(:error) do
          Ductwork::Pipeline::DefinitionError.new("Definition block must be given").tap do |e|
            e.set_backtrace(
              [
                Rails.root.join("app/pipelines/my_pipeline.rb:4:in `<class:MyPipeline>'").to_s,
                "/gems/zeitwerk/loader/eager_load.rb:12:in `eager_load_dir'",
              ]
            )
          end
        end

        before do
          allow(Ductwork).to receive(:validate!).and_raise(error)
        end

        it "reports the error and exits without launching the processes" do
          expect do
            expect { described_class.start!(["start"]) }.to raise_error(SystemExit) do |exit|
              expect(exit.status).to eq(1)
            end
          end.to output(
            <<~REPORT
              ductwork failed to validate your step and pipeline definitions

                Ductwork::Pipeline::DefinitionError: Definition block must be given
                  #{Rails.root.join("app/pipelines/my_pipeline.rb:4:in `<class:MyPipeline>'")}
            REPORT
          ).to_stderr

          expect(Ductwork::Processes::Launcher).not_to have_received(:start_processes!)
        end

        it "reports the whole backtrace at the debug level" do
          allow(logger).to receive(:debug?).and_return(true)

          expect do
            expect { described_class.start!(["start"]) }.to raise_error(SystemExit)
          end.to output(/eager_load_dir/).to_stderr
        end
      end
    end

    context "when given the health command" do
      it "does not validate the steps and pipelines" do
        described_class.start!(["health"])

        expect(Ductwork).not_to have_received(:validate!)
      end

      it "calls the health check" do
        described_class.start!(["health"])

        expect(Ductwork::Processes::HealthCheck).to have_received(:run)
      end
    end
  end
end
