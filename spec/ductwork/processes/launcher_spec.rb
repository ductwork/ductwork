# frozen_string_literal: true

RSpec.describe Ductwork::Processes::Launcher do
  describe ".start_processes!" do
    before do
      Ductwork.configuration = Ductwork::Configuration.new(role:)
    end

    context "when the role is 'all'" do
      let(:role) { "all" }

      it "starts the supervisor" do
        runner = instance_double(Ductwork::Processes::SupervisorRunner, run: nil)
        allow(Ductwork::Processes::SupervisorRunner).to receive(:new).and_return(runner)

        described_class.start_processes!

        expect(Ductwork::Processes::SupervisorRunner).to have_received(:new)
        expect(runner).to have_received(:run)
      end
    end

    context "when the role is 'advancer'" do
      let(:role) { "advancer" }

      it "starts the pipeline advancer" do
        runner = instance_double(Ductwork::Processes::PipelineAdvancerRunner, run: nil)
        allow(Ductwork::Processes::PipelineAdvancerRunner).to receive(:new).and_return(runner)

        described_class.start_processes!

        expect(Ductwork::Processes::PipelineAdvancerRunner).to have_received(:new).with(no_args)
        expect(runner).to have_received(:run)
      end
    end

    context "when the role is 'worker'" do
      let(:role) { "worker" }

      it "starts the job worker" do
        runner = instance_double(Ductwork::Processes::JobWorkerRunner, run: nil)
        allow(Ductwork::Processes::JobWorkerRunner).to receive(:new).and_return(runner)

        described_class.start_processes!

        expect(Ductwork::Processes::JobWorkerRunner).to have_received(:new).with(no_args)
        expect(runner).to have_received(:run)
      end
    end
  end
end
