# frozen_string_literal: true

module Ductwork
  class Job < Ductwork::Record
    belongs_to :step, class_name: "Ductwork::Step"
    has_many :executions, class_name: "Ductwork::Execution", foreign_key: "job_id", dependent: :destroy

    validates :klass, presence: true
    validates :started_at, presence: true
    validates :input_args, presence: true

    def self.enqueue(step, *args)
      job = step.create_job!(
        klass: step.klass,
        started_at: Time.current,
        input_args: JSON.dump({ args: })
      )
      execution = job.executions.create!(
        started_at: Time.current,
        retry_count: 0,
        crash_count: 0
      )
      execution.create_availability!(
        started_at: Time.current,
        pipeline_klass: step.run.pipeline_klass
      )

      Ductwork.logger.info(
        msg: "Job enqueued",
        job_id: job.id,
        job_klass: job.klass
      )

      job
    end

    def return_value
      if output_payload.present?
        JSON.parse(output_payload).fetch("payload", nil)
      end
    end
  end
end
