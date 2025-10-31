# frozen_string_literal: true

module Ductwork
  class Job < Ductwork::Record
    belongs_to :step, class_name: "Ductwork::Step"
    has_many :executions, class_name: "Ductwork::Execution", foreign_key: "job_id", dependent: :destroy

    validates :klass, presence: true
    validates :started_at, presence: true
    validates :input_args, presence: true

    def self.claim_latest
      process_id = ::Process.pid
      id = Ductwork::Availability
           .where(completed_at: nil)
           .order(:created_at)
           .limit(1)
           .pluck(:id)
           .first

      if id.present?
        # TODO: probably makes sense to use SQL here instead of relying
        # on ActiveRecord to construct the correct `UPDATE` query
        rows_updated = nil
        Ductwork::Record.transaction do
          rows_updated = Ductwork::Availability
                         .where(id:, completed_at: nil)
                         .update_all(completed_at: Time.current, process_id:)
          Ductwork::Execution
            .joins(:availability)
            .where(completed_at: nil)
            .where(ductwork_availabilities: { id: id })
            .update_all(process_id: process_id)
        end

        if rows_updated == 1
          Ductwork.configuration.logger.debug(
            msg: "Job claimed",
            role: :job_worker,
            process_id: process_id,
            availability_id: id
          )
          Ductwork::Job
            .joins(executions: :availability)
            .find_by(ductwork_availabilities: { id:, process_id: })
        else
          Ductwork.configuration.logger.debug(
            msg: "Did not claim job, avoided race condition",
            role: :job_worker,
            process_id: process_id,
            availability_id: id
          )
          nil
        end
      end
    end

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
