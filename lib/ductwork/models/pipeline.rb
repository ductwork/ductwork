# frozen_string_literal: true

module Ductwork
  class Pipeline < Ductwork::Record
    has_many :steps, class_name: "Ductwork::Step", foreign_key: "pipeline_id", dependent: :destroy

    validates :name, uniqueness: true, presence: true
    validates :status, presence: true
    validates :triggered_at, presence: true

    enum :status,
         pending: "pending",
         in_progress: "in_progress",
         completed: "completed"

    def self.inherited(subclass)
      super
      subclass.class_eval do
        default_scope { where(name: name.to_s) }
      end
    end

    class DefinitionError < StandardError; end

    class << self
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

      def trigger(*args)
        pipeline, job = nil

        Record.transaction do
          pipeline = create_pipeline!
          steps = create_steps!(pipeline)
          assign_step_order!(steps)
          job = create_job!(steps.first)
        end

        enqueue_job(job, *args)

        pipeline
      end

      private

      def create_pipeline!
        create!(
          name: name.to_s,
          status: :in_progress,
          triggered_at: Time.current
        )
      end

      def create_steps!(pipeline)
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
            pipeline: pipeline,
            step_type: type,
            klass: step.klass,
            status: :in_progress,
            started_at: started_at
          )
        end
      end

      def assign_step_order!(steps)
        steps.each_with_index do |step, index|
          step.previous_step = if index.positive?
                                 steps[index - 1]
                               end
          step.next_step = if !steps[index + 1].nil?
                             steps[index + 1]
                           end
          step.save!
        end
      end

      def create_job!(step)
        Job.create!(
          adapter: Ductwork.configuration.adapter,
          jid: SecureRandom.uuid,
          enqueued_at: Time.current,
          status: "running",
          step: step
        )
      end

      def enqueue_job(job, *args)
        if job.sidekiq?
          Ductwork::SidekiqWrapperJob.client_push(
            "queue" => Ductwork.configuration.job_queue,
            "class" => "Ductwork::SidekiqWrapperJob",
            "args" => [job.step.klass] + args,
            "jid" => job.jid
          )
        end
      end
    end
  end
end
