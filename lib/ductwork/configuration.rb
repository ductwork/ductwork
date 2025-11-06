# frozen_string_literal: true

module Ductwork
  class Configuration
    DEFAULT_ENV = :default
    DEFAULT_FILE_PATH = "config/ductwork.yml"
    DEFAULT_JOB_WORKER_COUNT = 5 # threads
    DEFAULT_JOB_WORKER_MAX_RETRY = 3 # attempts
    DEFAULT_JOB_WORKER_POLLING_TIMEOUT = 1 # second
    DEFAULT_JOB_WORKER_SHUTDOWN_TIMEOUT = 20 # seconds
    DEFAULT_PIPELINE_POLLING_TIMEOUT = 1 # second
    DEFAULT_SUPERVISOR_POLLING_TIMEOUT = 1 # second
    DEFAULT_SUPERVISOR_SHUTDOWN_TIMEOUT = 30 # seconds
    DEFAULT_LOGGER = ::Logger.new($stdout)
    PIPELINES_WILDCARD = "*"

    attr_accessor :logger
    attr_writer :job_worker_polling_timeout, :job_worker_shutdown_timeout,
                :pipeline_polling_timeout, :supervisor_polling_timeout,
                :supervisor_shutdown_timeout, :job_worker_max_retry

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
        Dir
          .glob("**/*.rb", base: "app/pipelines")
          .map { |path| path.delete_suffix(".rb").camelize }
      else
        raw_pipelines.map(&:strip)
      end
    end

    def database
      config[:database]
    end

    def job_worker_count(pipeline)
      raw_count = config.dig(:job_worker, :count) || DEFAULT_JOB_WORKER_COUNT

      if raw_count.is_a?(Hash)
        raw_count[pipeline.to_sym]
      else
        raw_count
      end
    end

    def job_worker_max_retry
      @job_worker_max_retry ||= fetch_job_worker_max_retry
    end

    def job_worker_polling_timeout
      @job_worker_polling_timeout ||= fetch_job_worker_polling_timeout
    end

    def job_worker_shutdown_timeout
      @job_worker_shutdown_timeout ||= fetch_job_worker_shutdown_timeout
    end

    def pipeline_polling_timeout
      @pipeline_polling_timeout ||= fetch_pipeline_polling_timeout
    end

    def supervisor_polling_timeout
      @supervisor_polling_timeout ||= fetch_supervisor_polling_timeout
    end

    def supervisor_shutdown_timeout
      @supervisor_shutdown_timeout ||= fetch_supervisor_shutdown_timeout
    end

    private

    attr_reader :config

    def fetch_job_worker_max_retry
      config.dig(:job_worker, :max_retry) ||
        DEFAULT_JOB_WORKER_MAX_RETRY
    end

    def fetch_job_worker_polling_timeout
      config.dig(:job_worker, :polling_timeout) ||
        DEFAULT_JOB_WORKER_POLLING_TIMEOUT
    end

    def fetch_job_worker_shutdown_timeout
      config.dig(:job_worker, :shutdown_timeout) ||
        DEFAULT_JOB_WORKER_SHUTDOWN_TIMEOUT
    end

    def fetch_pipeline_polling_timeout
      config.dig(:pipeline, :polling_timeout) ||
        DEFAULT_PIPELINE_POLLING_TIMEOUT
    end

    def fetch_supervisor_polling_timeout
      config.dig(:supervisor, :polling_timeout) ||
        DEFAULT_SUPERVISOR_POLLING_TIMEOUT
    end

    def fetch_supervisor_shutdown_timeout
      config.dig(:supervisor, :shutdown_timeout) ||
        DEFAULT_SUPERVISOR_SHUTDOWN_TIMEOUT
    end
  end
end
