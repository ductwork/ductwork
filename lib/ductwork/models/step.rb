# frozen_string_literal: true

module Ductwork
  class Step < Ductwork::Record
    belongs_to :pipeline, class_name: "Ductwork::Pipeline"
    has_one :job, class_name: "Ductwork::Job", foreign_key: "step_id", dependent: :destroy

    validates :node, presence: true
    validates :klass, presence: true
    validates :status, presence: true
    validates :to_transition, presence: true

    enum :status,
         pending: "pending",
         in_progress: "in_progress",
         waiting: "waiting",
         advancing: "advancing",
         failed: "failed",
         completed: "completed"

    enum :to_transition,
         start: "start",
         default: "default", # `chain` is used by AR
         divide: "divide",
         combine: "combine",
         expand: "expand",
         collapse: "collapse",
         divert: "divert",
         converge: "converge",
         damper: "damper"

    def self.build_for_execution(pipeline_id, *, **)
      instance = allocate
      instance.instance_variable_set(:@pipeline_id, pipeline_id)
      instance.send(:initialize, *, **)
      instance
    end

    def pipeline_id
      @pipeline_id || (@attributes && super)
    end

    def context
      @_context ||= Ductwork::Context.new(pipeline_id)
    end
  end
end
