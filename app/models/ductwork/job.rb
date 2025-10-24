# frozen_string_literal: true

module Ductwork
  class Job < Ductwork::Record
    belongs_to :step, class_name: "Ductwork::Step"
    has_many :executions, class_name: "Ductwork::Execution", foreign_key: "job_id", dependent: :destroy

    validates :klass, presence: true
    validates :started_at, presence: true
    validates :input_args, presence: true

    def self.enqueue(job_klass, step, *args)
      job = step.create_job!(
        klass: job_klass,
        started_at: Time.current,
        input_args: JSON.dump(args)
      )
      execution = job.executions.create!(
        started_at: Time.current
      )
      execution.create_availability!(
        started_at: Time.current
      )

      job
    end
  end
end
