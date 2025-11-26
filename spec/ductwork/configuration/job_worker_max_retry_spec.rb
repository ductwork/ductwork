# frozen_string_literal: true

RSpec.describe Ductwork::Configuration, "#job_worker_max_retry" do
  include ConfigurationFileHelper

  context "when the config file exists" do
    let(:data) do
      <<~DATA
        default: &default
          job_worker:
            max_retry: 5

        test:
          <<: *default
      DATA
    end

    before do
      create_default_config_file
    end

    it "returns the timeout" do
      config = described_class.new

      expect(config.job_worker_max_retry).to eq(5)
    end

    context "with pipeline-level configuration" do
      let(:data) do
        <<~DATA
          default: &default
            job_worker:
              max_retry:
                default: 10
                MyPipelineA: 10_000

          test:
            <<: *default
        DATA
      end

      it "returns the timeout" do
        config = described_class.new

        max_retry = config.job_worker_max_retry(pipeline: "MyPipelineA")

        expect(max_retry).to eq(10_000)
      end

      it "returns the default if given no pipeline" do
        config = described_class.new

        max_retry = config.job_worker_max_retry

        expect(max_retry).to eq(10)
      end

      it "returns the default if no pipeline config" do
        config = described_class.new

        max_retry = config.job_worker_max_retry(pipeline: "foobar")

        expect(max_retry).to eq(10)
      end
    end

    context "with step-level configuration" do
      let(:data) do
        <<~DATA
          default: &default
            job_worker:
              max_retry:
                default: 10
                MyPipelineA:
                  default: 10_000
                  MyStep1: 5_000

          test:
            <<: *default
        DATA
      end

      it "returns the timeout" do
        config = described_class.new

        max_retry = config.job_worker_max_retry(pipeline: "MyPipelineA", step: "MyStep1")

        expect(max_retry).to eq(5_000)
      end

      it "returns the pipeline-level default if no step config" do
        config = described_class.new

        max_retry = config.job_worker_max_retry(pipeline: "MyPipelineA", step: "MyStep2")

        expect(max_retry).to eq(10_000)
      end

      it "returns the base default if no pipeline-level default" do
        config = described_class.new

        max_retry = config.job_worker_max_retry(pipeline: "MyPipelineB", step: "MyStep1")

        expect(max_retry).to eq(10)
      end
    end
  end

  context "when no config file exists" do
    it "returns the base default" do
      config = described_class.new

      expect(config.job_worker_max_retry).to eq(
        described_class::DEFAULT_JOB_WORKER_MAX_RETRY
      )
    end
  end
end
