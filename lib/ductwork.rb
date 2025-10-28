# frozen_string_literal: true

require "logger"
require "active_support"
require "active_support/core_ext/hash"
require "active_support/core_ext/time"
require "active_record"
require "securerandom"
require "rails/engine"
require "zeitwerk"
require "ductwork/engine"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("cli" => "CLI")
loader.ignore("#{__dir__}/generators")
loader.setup

module Ductwork
  class << self
    attr_accessor :configuration

    def pipelines
      @_pipelines ||= []
    end

    # NOTE: this is test interface only
    def reset!
      @_pipelines = nil
      @configuration = nil
    end
  end
end
