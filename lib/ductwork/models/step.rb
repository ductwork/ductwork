# frozen_string_literal: true

module Ductwork
  class Step < Ductwork::Record
    belongs_to :run, class_name: "Ductwork::Run"
    belongs_to :branch, class_name: "Ductwork::Branch"
    belongs_to :source_step, class_name: "Ductwork::Step", optional: true
    has_many :derived_steps, class_name: "Ductwork::Step", foreign_key: :source_step_id, dependent: :destroy
    has_one :job, class_name: "Ductwork::Job", foreign_key: "step_id", dependent: :destroy
    has_one :in_transition, class_name: "Ductwork::Transition", foreign_key: "in_step_id", dependent: :destroy
    has_one :out_transition, class_name: "Ductwork::Transition", foreign_key: "out_step_id", dependent: :destroy

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
         dampen: "dampen"

    def self.build_for_execution(run_id, *, **)
      instance = allocate
      instance.instance_variable_set(:@run_id, run_id)
      instance.send(:initialize, *, **)
      instance
    end

    alias_attribute :idempotency_key, :id

    def run_id
      @run_id || (@attributes && super)
    end

    # The result_type of the most recent execution to finish for this step's
    # job, used to distinguish *why* a step failed (e.g. `errored!` writes
    # "failure", `crashed!` writes "process_crashed"). Returns nil when no
    # execution has produced a result yet.
    def terminal_result_type
      return if job.blank?

      job.executions
         .joins(:result)
         .order(created_at: :desc)
         .pick("ductwork_results.result_type")
    end

    def context
      @_context ||= Ductwork::Context.new(run_id)
    end
  end
end
