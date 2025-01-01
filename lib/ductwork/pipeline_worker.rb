# frozen_string_literal: true

module Ductwork
  class PipelineWorker
    def initialize(pipeline_name)
      @pipeline_name = pipeline_name
    end

    def run; end

    private

    attr_reader :pipeline_name
  end
end
