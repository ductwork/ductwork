# frozen_string_literal: true

module Ductwork
  class Step < Ductwork::Record
    belongs_to :pipeline, class_name: "Ductwork::Pipeline"
    belongs_to :next_step, class_name: "Ductwork::Step", optional: true
    has_one :previous_step, class_name: "Ductwork::Step", foreign_key: "next_step_id"

    validates :klass, presence: true
    validates :pipeline_id, presence: true
    validates :status, presence: true
    validates :step_type, presence: true

    enum :status,
         pending: "pending",
         in_progress: "in_progress",
         completed: "completed"

    enum :step_type,
         start: "start",
         default: "default", # `chain` is used by AR
         expand: "expand",
         collapse: "collapse"
  end
end
