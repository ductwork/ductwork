# frozen_string_literal: true

module Ductwork
  module Pipeline
    class DefinitionError < StandardError; end

    module ClassMethods
      attr_reader :pipeline_definition

      def define(&block)
        if !block_given?
          raise DefinitionError, "Definition block must be given"
        end

        if pipeline_definition
          raise DefinitionError, "Pipeline has already been defined"
        end

        builder = DefinitionBuilder.new

        block.call(builder)

        @pipeline_definition = builder.complete!

        Ductwork.pipelines << to_s
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end
  end
end
