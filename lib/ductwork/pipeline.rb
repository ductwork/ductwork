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

        @pipeline_definition = builder.complete

        Ductwork.pipelines << name.to_s
      end

      def trigger(_args)
        Record.transaction do
          instance = create_pipeline_instance
          steps = create_steps(instance)
          steps.each_with_index do |step, index|
            step.previous_step = if index.positive?
                                   steps[index - 1]
                                 end
            step.next_step = if !steps[index + 1].nil?
                               steps[index + 1]
                             end
            step.save!
          end

          instance
        end
      end

      private

      def create_pipeline_instance
        PipelineInstance.create!(
          name: name.to_s,
          status: :in_progress,
          triggered_at: Time.current
        )
      end

      def create_steps(instance)
        pipeline_definition.steps.map do |step|
          started_at = if step.first?
                         Time.current
                       end
          type = if step.type.to_sym == :chain
                   :default
                 else
                   step.type
                 end

          Step.create!(
            pipeline: instance,
            step_type: type,
            klass: step.klass,
            started_at: started_at
          )
        end
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end
  end
end
