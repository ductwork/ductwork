# frozen_string_literal: true

module Ductwork
  class Configuration
    DEFAULT_ENV = :default
    DEFAULT_FILE_PATH = "config/ductwork.yml"
    DEFAULT_JOB_WORKER_COUNT = 5 # threads
    DEFAULT_JOB_WORKER_SHUTDOWN_TIMEOUT = 30 # seconds
    DEFAULT_LOGGER = ::Logger.new($stdout)
    PIPELINES_WILDCARD = "*"

    class AdapterError < StandardError; end

    attr_accessor :logger

    def initialize(path: DEFAULT_FILE_PATH)
      full_path = Pathname.new(path)
      data = ActiveSupport::ConfigurationFile.parse(full_path).deep_symbolize_keys
      env = defined?(Rails) ? Rails.env.to_sym : DEFAULT_ENV
      @config = data[env]
    rescue Errno::ENOENT
      @config = {}
    end

    def pipelines
      raw_pipelines = config[:pipelines] || []

      if raw_pipelines == PIPELINES_WILDCARD
        Ductwork.pipelines
      else
        raw_pipelines.map(&:strip)
      end
    end

    def job_worker_count(pipeline)
      raw_count = config.dig(:job_worker, :count) || DEFAULT_JOB_WORKER_COUNT

      if raw_count.is_a?(Hash)
        raw_count[pipeline.to_sym]
      else
        raw_count
      end
    end

    def job_worker_shutdown_timeout
      config.dig(:job_worker, :shutdown_timeout) ||
        DEFAULT_JOB_WORKER_SHUTDOWN_TIMEOUT
    end

    private

    attr_reader :config
  end
end
