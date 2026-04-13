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

    def resolve_terminal_state! # rubocop:todo Metrics/AbcSize
      halted = false

      Ductwork::Record.transaction do
        lock!

        next if halted? || completed?
        next if branches.where.not(status: %w[completed halted]).exists?

        if branches.halted.exists?
          halted = true
          pipeline.update!(status: "halted")
          update!(status: "halted", halted_at: Time.current)

          Ductwork.logger.warn(
            msg: "Pipeline halted",
            pipeline_id: pipeline.id,
            run_id: id
          )

        else
          pipeline.update!(status: "completed")
          update!(status: "completed", completed_at: Time.current)

          Ductwork.logger.info(
            msg: "Pipeline completed",
            pipeline_id: pipeline.id,
            run_id: id
          )
        end
      end
    ensure
      if halted
        klass = parsed_definition.dig(:metadata, :on_halt, :klass)

        if klass.present?
          reasons = branches.halted.pluck(:halt_reason)

          Object.const_get(klass).new(reasons).execute
        end
      end
    end
  end
end
