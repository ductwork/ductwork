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
          workers:
            - pipelines: "PipelineA, PipelineB"

        development:
          <<: *default

        test:
          workers:
            - pipelines: "*"

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

  describe "#adapter" do
    let(:config_file) do
      Tempfile.new("ductwork.yml").tap do |file|
        data = <<~DATA
          test:
            adapter: #{adapter}
            workers:
              - pipelines: "*"
        DATA
        file.write(data)
        file.rewind
      end
    end

    after do
      config_file.close
      config_file.unlink
    end

    context "when the adapter is supported" do
      let(:adapter) { "sidekiq" }

      it "returns the configured adapter" do
        config = described_class.new(path: config_file.path)

        expect(config.adapter).to eq("sidekiq")
      end

      it "returns the default adapter if none is configured" do
        path = Rails.root.join("config/ductwork.yml")

        config = described_class.new(path:)

        expect(config.adapter).to eq("activejob")
      end
    end

    context "when the adapter is not supported" do
      let(:adapter) { "silly-job" }

      it "raises an error" do
        config = described_class.new(path: config_file.path)

        expect do
          config.adapter
        end.to raise_error(described_class::AdapterError, "Adapter is not supported")
      end
    end
  end
end
