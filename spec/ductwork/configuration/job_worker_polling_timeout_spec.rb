# frozen_string_literal: true

RSpec.describe Ductwork::Configuration, "#job_worker_polling_timeout" do
  include ConfigurationFileHelper

  context "when the config file exists" do
    let(:data) do
      <<~DATA
        default: &default
          job_worker:
            polling_timeout: 2

        test:
          <<: *default
      DATA
    end

    before do
      create_default_config_file
    end

    it "returns the timeout" do
      config = described_class.new

      expect(config.job_worker_polling_timeout).to eq(2)
    end

    it "returns the manually set value" do
      config = described_class.new
      config.job_worker_polling_timeout = 0.1

      expect(config.job_worker_polling_timeout).to eq(0.1)
    end

    context "with pipeline-level configuration" do
      let(:data) do
        <<~DATA
          default: &default
            job_worker:
              polling_timeout:
                default: 1
                MyPipelineA: 0.5
          test:
            <<: *default
        DATA
      end

      it "returns the configured value" do
        config = described_class.new

        expect(config.job_worker_polling_timeout("MyPipelineA")).to eq(0.5)
      end

      it "returns the default if no pipeline configuration" do
        config = described_class.new

        expect(config.job_worker_polling_timeout("MyPipelineB")).to eq(1)
      end
    end
  end

  context "when no config file exists" do
    it "returns the base default" do
      config = described_class.new

      expect(config.job_worker_polling_timeout).to eq(
        described_class::DEFAULT_JOB_WORKER_POLLING_TIMEOUT
      )
    end
  end
end
