# frozen_string_literal: true

require "ductwork/cli"

RSpec.describe Ductwork::CLI do
  it "parses arguments, loads configuration, and starts the worker launcher" do
    config = instance_double(Ductwork::Configuration, :logger= => nil)
    allow(Ductwork::SupervisorRunner).to receive(:start!)
    allow(Ductwork::Configuration).to receive(:new).and_return(config)

    described_class.start!([])

    expect(config).to have_received(:logger=).with(Ductwork::Configuration::DEFAULT_LOGGER)
    expect(Ductwork::Configuration).to have_received(:new)
    expect(Ductwork::SupervisorRunner).to have_received(:start!)
  end
end
