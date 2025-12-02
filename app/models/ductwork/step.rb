# frozen_string_literal: true

module Ductwork
  class Step < Ductwork::Record
    belongs_to :pipeline, class_name: "Ductwork::Pipeline"
    has_one :job, class_name: "Ductwork::Job", foreign_key: "step_id", dependent: :destroy

    validates :klass, presence: true
    validates :status, presence: true
    validates :step_type, presence: true

    enum :status,
         pending: "pending",
         in_progress: "in_progress",
         waiting: "waiting",
         advancing: "advancing",
         failed: "failed",
         completed: "completed"

    enum :step_type,
         start: "start",
         default: "default", # `chain` is used by AR
         divide: "divide",
         combine: "combine",
         expand: "expand",
         collapse: "collapse"
  end
end
