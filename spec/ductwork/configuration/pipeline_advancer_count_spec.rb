# frozen_string_literal: true

RSpec.describe Ductwork::Configuration, "#pipeline_advancer_count" do
  include ConfigurationFileHelper

  context "when the config file exists" do
    let(:data) do
      <<~DATA
        default: &default
          pipeline_advancer:
            count: 15

        test:
          <<: *default
      DATA
    end

    before do
      create_default_config_file
    end

    it "returns the count" do
      config = described_class.new

      expect(config.pipeline_advancer_count).to eq(15)
    end

    it "returns the manually set value" do
      config = described_class.new

      config.pipeline_advancer_count = 10

      expect(config.pipeline_advancer_count).to eq(10)
    end

    context "with pipeline-level configuration" do
      let(:data) do
        <<~DATA
          default: &default
            pipeline_advancer:
              count:
                default: 5
                MyPipelineA: 7

          test:
            <<: *default
        DATA
      end

      it "returns the configured value" do
        config = described_class.new

        expect(config.pipeline_advancer_count("MyPipelineA")).to eq(7)
      end

      it "returns the base default if no pipeline configuration" do
        config = described_class.new

        expect(config.pipeline_advancer_count("MyPipelineB")).to eq(5)
      end

      it "returns the base default if no pipeline is given" do
        config = described_class.new

        expect(config.pipeline_advancer_count).to eq(5)
      end
    end
  end

  context "when no config file exists" do
    it "returns the default" do
      config = described_class.new

      expect(config.pipeline_advancer_count).to eq(
        described_class::DEFAULT_PIPELINE_ADVANCER_THREAD_COUNT
      )
    end
  end
end
