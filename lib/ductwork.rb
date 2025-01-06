# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/core_ext/hash"
require "active_support/core_ext/time"
require "rails/railtie"

require_relative "ductwork/configuration"
require_relative "ductwork/definition"
require_relative "ductwork/definition_builder"
require_relative "ductwork/pipeline"
require_relative "ductwork/pipeline_worker"
require_relative "ductwork/step_definition"
require_relative "ductwork/supervisor"
require_relative "ductwork/version"
require_relative "ductwork/worker_launcher"
require_relative "ductwork/railtie" if defined?(Rails)

module Ductwork
  def self.pipelines
    @_pipelines ||= []
  end

  # NOTE: this is test interface only
  def self.reset!
    @_pipelines = nil
  end
end
