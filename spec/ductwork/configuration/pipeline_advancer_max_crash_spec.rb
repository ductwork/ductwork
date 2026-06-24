# frozen_string_literal: true

RSpec.describe Ductwork::Configuration, "#pipeline_advancer_max_crash" do
  include ConfigurationFileHelper

  context "when the config file exists" do
    let(:data) do
      <<~DATA
        default: &default
          pipeline_advancer:
            max_crash: 4

        test:
          <<: *default
      DATA
    end

    before do
      create_default_config_file
    end

    it "returns the max crash" do
      config = described_class.new

      expect(config.pipeline_advancer_max_crash).to eq(4)
    end

    it "returns the manually set value" do
      config = described_class.new
      config.pipeline_advancer_max_crash = 2

      expect(config.pipeline_advancer_max_crash).to eq(2)
    end
  end

  context "when no config file exists" do
    it "returns the max crash default" do
      config = described_class.new

      expect(config.pipeline_advancer_max_crash).to eq(
        described_class::DEFAULT_PIPELINE_ADVANCER_MAX_CRASH
      )
    end
  end
end
