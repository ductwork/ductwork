# frozen_string_literal: true

require "fileutils"

RSpec.describe Ductwork::Configuration do
  describe "initialization" do
    it "raises if no config file at path" do
      expect do
        described_class.new
      end.to raise_error(described_class::FileError, "Missing configuration file")
    end
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

    after do
      cleanup
    end

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
      Ductwork.pipelines << "PipelineA"
      Ductwork.pipelines << "PipelineB"
      Ductwork.pipelines << "PipelineC"

      config = described_class.new(path: config_file.path)

      expect(config.pipelines).to eq(%w[PipelineA PipelineB PipelineC])
    end
  end

  describe "#job_worker_count" do
    let(:config_file) { create_temp_file }

    before do
      create_default_config_file
    end

    after do
      cleanup
    end

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
        config = described_class.new

        expect(config.job_worker_count("PipelineB")).to eq(10)
      end
    end
  end

  describe "#job_worker_shutdown_timeout" do
    let(:config_file) { create_temp_file }
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

    after do
      cleanup
    end

    it "returns the timeout" do
      config = described_class.new

      expect(config.job_worker_shutdown_timeout).to eq(30)
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
    config_file.close
    config_file.unlink

    if File.directory?("config")
      FileUtils.rm_rf("config")
    end
  end
end
