# frozen_string_literal: true

module Ductwork
  class Run < Ductwork::Record
    belongs_to :pipeline, class_name: "Ductwork::Pipeline"
    has_many :branches,
             class_name: "Ductwork::Branch",
             foreign_key: "run_id",
             dependent: :destroy
    has_many :steps,
             class_name: "Ductwork::Step",
             foreign_key: "run_id",
             dependent: :destroy
    has_many :tuples,
             class_name: "Ductwork::Tuple",
             foreign_key: "run_id",
             dependent: :destroy

    validates :pipeline_klass, presence: true
    validates :definition, presence: true
    validates :definition_sha1, presence: true
    validates :status, presence: true
    validates :started_at, presence: true
    validates :triggered_at, presence: true

    enum :status,
         pending: "pending",
         in_progress: "in_progress",
         waiting: "waiting",
         advancing: "advancing",
         halted: "halted",
         dampened: "dampened",
         completed: "completed"

    def parsed_definition
      @parsed_definition ||= JSON.parse(definition).with_indifferent_access
    end
  end
end
