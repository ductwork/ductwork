# frozen_string_literal: true

module Ductwork
  class Job < Ductwork::Record
    belongs_to :step, class_name: "Ductwork::Step"
    has_many :executions, class_name: "Ductwork::Execution", foreign_key: "job_id", dependent: :destroy

    validates :klass, presence: true
    validates :started_at, presence: true
    validates :input_args, presence: true
  end
end
