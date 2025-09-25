# frozen_string_literal: true

require "ductwork/cli"

RSpec.describe Ductwork::CLI do
  it "parses arguments, loads configuration, and starts the worker launcher" do
    allow(Ductwork::WorkerLauncher).to receive(:start!)
    allow(Ductwork::Configuration).to receive(:new)

    described_class.start!([])

    expect(Ductwork::Configuration).to have_received(:new)
    expect(Ductwork::WorkerLauncher).to have_received(:start!)
  end
end
