# frozen_string_literal: true

RSpec.describe Ductwork do
  let(:block) { -> { puts "hi" } }

  it "has a version number" do
    expect(Ductwork::VERSION).not_to be_nil
  end

  describe ".loader" do
    it "sets the code loader attribute when loading" do
      expect(described_class.loader).to be_present
    end
  end

  describe ".eager_load" do
    it "calls eager load on the code loader" do
      allow(described_class.loader).to receive(:eager_load)

      described_class.eager_load

      expect(described_class.loader).to have_received(:eager_load)
    end
  end

  describe ".wrap_with_app_executor" do
    it "yields if no app executor is configured" do
      expect do |block|
        described_class.wrap_with_app_executor(&block)
      end.to yield_control
    end

    it "wraps the block with the app executor when configured" do
      # NOTE: we have to disable rubocop here because rails' app executor
      # is an anonymous class
      # rubocop:disable RSpec/VerifiedDoubles
      executor = double(Rails.application.executor, wrap: nil)
      # rubocop:enable RSpec/VerifiedDoubles
      described_class.app_executor = executor

      expect do |block|
        described_class.wrap_with_app_executor(&block)

        expect(executor).to have_received(:wrap).with(&block)
      end
    end
  end

  describe ".hooks" do
    it "returns an empty set of hooks if nothing is configured" do
      described_class.hooks = nil

      expect(described_class.hooks).to eq(
        {
          supervisor: { start: [], stop: [] },
          advancer: { start: [], stop: [] },
          worker: { start: [], stop: [] },
        }
      )
    end
  end

  describe ".on_supervisor_start" do
    it "adds the block to the collection of lifecycle hooks" do
      described_class.on_supervisor_start(&block)

      expect(described_class.hooks.dig(:supervisor, :start)).to eq([block])
    end
  end

  describe ".on_supervisor_stop" do
    it "adds the block to the collection of lifecycle hooks" do
      described_class.on_supervisor_stop(&block)

      expect(described_class.hooks.dig(:supervisor, :stop)).to eq([block])
    end
  end

  describe ".on_advancer_start" do
    it "adds the block to the collection of lifecycle hooks" do
      described_class.on_advancer_start(&block)

      expect(described_class.hooks.dig(:advancer, :start)).to eq([block])
    end
  end

  describe ".on_advancer_stop" do
    it "adds the block to the collection of lifecycle hooks" do
      described_class.on_advancer_stop(&block)

      expect(described_class.hooks.dig(:advancer, :stop)).to eq([block])
    end
  end

  describe ".on_worker_start" do
    it "adds the block to the collection of lifecycle hooks" do
      described_class.on_worker_start(&block)

      expect(described_class.hooks.dig(:worker, :start)).to eq([block])
    end
  end

  describe ".on_worker_stop" do
    it "adds the block to the collection of lifecycle hooks" do
      described_class.on_worker_stop(&block)

      expect(described_class.hooks.dig(:worker, :stop)).to eq([block])
    end
  end

  describe ".defined_pipelines" do
    it "returns an empty array if nothing is configured" do
      described_class.defined_pipelines = nil

      expect(described_class.defined_pipelines).to eq([])
    end
  end
end
