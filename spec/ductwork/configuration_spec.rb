# frozen_string_literal: true

require "fileutils"

RSpec.describe Ductwork::Configuration do
  after do
    cleanup
  end

  describe "#pipelines" do
    let(:data) do
      <<~DATA
        default: &default
          pipelines:
            - PipelineA
            - PipelineB

        development:
          <<: *default

        test:
          pipelines: "*"

        production:
          <<: *default
      DATA
    end
    let(:config_file) { create_temp_file }

    it "returns the pipelines from the config file at the given path" do
      rails = double(env: "development") # rubocop:disable RSpec/VerifiedDoubles
      stub_const("Rails", rails)

      config = described_class.new(path: config_file.path)

      expect(config.pipelines).to eq(%w[PipelineA PipelineB])
    end

    it "returns the pipelines from the default config file if no path given" do
      rails = double(env: "production") # rubocop:disable RSpec/VerifiedDoubles
      stub_const("Rails", rails)
      create_default_config_file

      config = described_class.new

      expect(config.pipelines).to eq(%w[PipelineA PipelineB])
    end

    it "returns all defined pipelines when wildcard is configured" do
      collection = %w[PipelineA PipelineB PipelineC]
      allow(Dir).to receive(:glob).and_return(collection)

      config = described_class.new(path: config_file.path)

      expect(config.pipelines).to eq(%w[PipelineA PipelineB PipelineC])
    end

    it "returns an empty collection when no config file exists" do
      config = described_class.new

      expect(config.pipelines).to be_empty
    end
  end

  describe "#database" do
    context "when the config file exists" do
      let(:data) do
        <<~DATA
          default: &default
            database: pipeline_db

          test:
            <<: *default
        DATA
      end

      before do
        create_default_config_file
      end

      it "returns the timeout" do
        config = described_class.new

        expect(config.database).to eq("pipeline_db")
      end
    end

    context "when no config file exists" do
      it "returns nil" do
        config = described_class.new

        expect(config.database).to be_nil
      end
    end
  end

  describe "#job_worker_count" do
    context "with a count for all pipelines" do
      let(:data) do
        <<~DATA
          default: &default
            job_worker:
              count: 5

          test:
            <<: *default
        DATA
      end

      it "returns the count" do
        create_default_config_file

        config = described_class.new

        expect(config.job_worker_count("foobar")).to eq(5)
      end
    end

    context "with a count for the specific pipeline" do
      let(:data) do
        <<~DATA
          default: &default
            job_worker:
              count:
                PipelineA: 5
                PipelineB: 10

          test:
            <<: *default
        DATA
      end

      it "returns the count" do
        create_default_config_file

        config = described_class.new

        expect(config.job_worker_count("PipelineB")).to eq(10)
      end
    end

    context "when no config file exists" do
      it "returns the default" do
        config = described_class.new

        expect(config.job_worker_count("foobar")).to eq(
          described_class::DEFAULT_JOB_WORKER_COUNT
        )
      end
    end
  end

  describe "#job_worker_max_retry" do
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
    end

    context "when no config file exists" do
      it "returns the default" do
        config = described_class.new

        expect(config.job_worker_max_retry).to eq(
          described_class::DEFAULT_JOB_WORKER_MAX_RETRY
        )
      end
    end
  end

  describe "#job_worker_polling_timeout" do
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
    end

    context "when no config file exists" do
      it "returns the default" do
        config = described_class.new

        expect(config.job_worker_polling_timeout).to eq(
          described_class::DEFAULT_JOB_WORKER_POLLING_TIMEOUT
        )
      end
    end
  end

  describe "#job_worker_shutdown_timeout" do
    context "when the config file exists" do
      let(:data) do
        <<~DATA
          default: &default
            job_worker:
              shutdown_timeout: 30

          test:
            <<: *default
        DATA
      end

      before do
        create_default_config_file
      end

      it "returns the timeout" do
        config = described_class.new

        expect(config.job_worker_shutdown_timeout).to eq(30)
      end
    end

    context "when no config file exists" do
      it "returns the default" do
        config = described_class.new

        expect(config.job_worker_shutdown_timeout).to eq(
          described_class::DEFAULT_JOB_WORKER_SHUTDOWN_TIMEOUT
        )
      end
    end
  end

  describe "#pipeline_polling_timeout" do
    context "when the config file exists" do
      let(:data) do
        <<~DATA
          default: &default
            pipeline_advancer:
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

        expect(config.pipeline_polling_timeout).to eq(2)
      end
    end

    context "when no config file exists" do
      it "returns the default" do
        config = described_class.new

        expect(config.pipeline_polling_timeout).to eq(
          described_class::DEFAULT_PIPELINE_POLLING_TIMEOUT
        )
      end
    end
  end

  describe "#pipeline_shutdown_timeout" do
    context "when the config file exists" do
      let(:data) do
        <<~DATA
          default: &default
            pipeline_advancer:
              shutdown_timeout: 25

          test:
            <<: *default
        DATA
      end

      before do
        create_default_config_file
      end

      it "returns the timeout" do
        config = described_class.new

        expect(config.pipeline_shutdown_timeout).to eq(25)
      end
    end

    context "when no config file exists" do
      it "returns the default" do
        config = described_class.new

        expect(config.pipeline_shutdown_timeout).to eq(
          described_class::DEFAULT_PIPELINE_SHUTDOWN_TIMEOUT
        )
      end
    end
  end

  describe "#supervisor_polling_timeout" do
    context "when the config file exists" do
      let(:data) do
        <<~DATA
          default: &default
            supervisor:
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

        expect(config.supervisor_polling_timeout).to eq(2)
      end
    end

    context "when no config file exists" do
      it "returns the default" do
        config = described_class.new

        expect(config.supervisor_polling_timeout).to eq(
          described_class::DEFAULT_SUPERVISOR_POLLING_TIMEOUT
        )
      end
    end
  end

  describe "#supervisor_shutdown_timeout" do
    context "when the config file exists" do
      let(:data) do
        <<~DATA
          default: &default
            supervisor:
              shutdown_timeout: 2

          test:
            <<: *default
        DATA
      end

      before do
        create_default_config_file
      end

      it "returns the timeout" do
        config = described_class.new

        expect(config.supervisor_shutdown_timeout).to eq(2)
      end
    end

    context "when no config file exists" do
      it "returns the default" do
        config = described_class.new

        expect(config.supervisor_shutdown_timeout).to eq(
          described_class::DEFAULT_SUPERVISOR_SHUTDOWN_TIMEOUT
        )
      end
    end
  end

  def create_temp_file
    Tempfile.new("ductwork.yml").tap do |file|
      file.write(data)
      file.rewind
    end
  end

  def create_default_config_file
    if !File.directory?("config")
      FileUtils.mkdir_p("config")
    end

    File.new("config/ductwork.yml", "w").tap do |file|
      file.write(data)
      file.rewind
    end
  end

  def cleanup
    if defined?(config_file)
      config_file.close
      config_file.unlink
    end

    if File.directory?("config")
      FileUtils.rm_rf("config")
    end
  end
end
