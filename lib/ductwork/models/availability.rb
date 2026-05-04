# frozen_string_literal: true

module Ductwork
  class Availability < Ductwork::Record
    belongs_to :execution, class_name: "Ductwork::Execution"
    belongs_to :process, class_name: "Ductwork::Process", optional: true

    validates :started_at, presence: true
    validates :pipeline_klass, presence: true

    def abandon!
      job = execution.job

      Ductwork::Record.transaction do
        execution.lock!
        execution.reload

        return if execution.completed_at.present?

        job.execution_crashed!(execution)
      end
    end
  end
end
