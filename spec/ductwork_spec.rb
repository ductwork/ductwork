# frozen_string_literal: true

RSpec.describe Ductwork do
  it "has a version number" do
    expect(Ductwork::VERSION).not_to be_nil
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

  describe ".defined_pipelines" do
    it "returns an empty array if nothing is configured" do
      described_class.defined_pipelines = nil

      expect(described_class.defined_pipelines).to eq([])
    end
  end
end
