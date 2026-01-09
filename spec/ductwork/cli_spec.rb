# frozen_string_literal: true

RSpec.describe Ductwork::CLI do
  describe ".start!" do
    let(:logger) { instance_double(Logger, :level= => nil) }
    let(:config) do
      instance_double(
        Ductwork::Configuration,
        logger_level: 0,
        logger_source: "default"
      )
    end

    before do
      ENV.delete("DUCTWORK_ROLE")
      allow(Ductwork::Processes::SupervisorRunner).to receive(:start!)
      allow(Ductwork::Configuration).to receive(:new).and_return(config)
      allow(Ductwork).to receive(:logger=).and_call_original
      allow(Ductwork).to receive(:logger).and_return(logger)
    end

    it "loads configuration" do
      described_class.start!([])

      expect(logger).to have_received(:level=).with(0)
      expect(Ductwork).to have_received(:logger=).with(Ductwork::Configuration::DEFAULT_LOGGER)
      expect(Ductwork::Configuration).to have_received(:new).with(role: nil)
    end

    it "loads the role from ENV" do
      ENV["DUCTWORK_ROLE"] = "supervisor"

      described_class.start!([])

      expect(Ductwork::Configuration).to have_received(:new).with(
        role: "supervisor"
      )
    end

    it "prints the banner" do
      expect do
        described_class.start!([])
      end.to output(<<-BANNER).to_stdout
  \e[1;37m
  ██████╗ ██╗   ██╗ ██████╗████████╗██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗
  ██╔══██╗██║   ██║██╔════╝╚══██╔══╝██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝
  ██║  ██║██║   ██║██║        ██║   ██║ █╗ ██║██║   ██║██████╔╝█████╔╝
  ██║  ██║██║   ██║██║        ██║   ██║███╗██║██║   ██║██╔══██╗██╔═██╗
  ██████╔╝╚██████╔╝╚██████╗   ██║   ╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗
  ╚═════╝  ╚═════╝  ╚═════╝   ╚═╝    ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
  ▒▒▓  ▒ ░▒▓▒ ▒ ▒ ░ ░▒ ▒  ░  ▒ ░░   ░ ▓░▒ ▒  ░ ▒░▒░▒░ ░ ▒▓ ░▒▓░▒ ▒▒ ▓▒
   ░ ▒  ▒ ░░▒░ ░ ░   ░  ▒       ░      ▒ ░ ░    ░ ▒ ▒░   ░▒ ░ ▒░░ ░▒ ▒░
    ░ ░  ░  ░░░ ░ ░ ░          ░        ░   ░  ░ ░ ░ ▒    ░░   ░ ░ ░░ ░
       ░       ░     ░ ░                    ░        ░ ░     ░     ░  ░
     ░               ░
  \e[0m
      BANNER
    end

    it "starts the supervisor" do
      described_class.start!([])

      expect(Ductwork::Processes::SupervisorRunner).to have_received(:start!)
    end
  end
end
