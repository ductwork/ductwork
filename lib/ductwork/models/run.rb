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

    def resolve_terminal_state!
      Ductwork::Record.transaction do
        lock_for_terminal_resolution!

        next if halted? || completed?
        next if branches.where.not(status: %w[completed halted]).exists?

        if branches.halted.exists?
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
    end

    # NOTE: Fires the host `on_halt` handler (at-most) once after the run has halted
    #
    # The handler is an observable side effect (it may page, refund, or emit an
    # external event), so it must run only after the halt is durably committed
    # and outside the advancer's `with_claim_fence` transaction; otherwise a
    # rolled-back commit (deadlock victim, dropped connection) would leave it
    # spuriously fired and double-firing on re-claim. `Branch#advance!` calls
    # this once the advancement has committed.
    #
    # The dispatch is claimed with an atomic `UPDATE ... WHERE`: only the
    # advancer that flips `on_halt_dispatched_at` from NULL runs the handler, and
    # only while the run is actually halted (a rolled-back halt never persists
    # `status`). That makes the handler at-most-once even across concurrent
    # advancers and re-claims.
    def dispatch_on_halt!
      klass = parsed_definition.dig(:metadata, :on_halt, :klass)

      return if klass.blank?

      claimed = self.class
                    .where(id: id, status: "halted", on_halt_dispatched_at: nil)
                    .update_all(on_halt_dispatched_at: Time.current)

      return if claimed.zero?

      begin
        reasons = branches.halted.pluck(:halt_reason)

        Object.const_get(klass).new(reasons).execute
      rescue StandardError => e
        Ductwork.logger.error(
          msg: "on_halt handler errored",
          run_id: id,
          error_klass: e.class.to_s,
          error_message: e.message
        )
      end
    end

    private

    # NOTE: a branch transition creates run-referencing rows (branch/step/job)
    # whose FK takes a `FOR KEY SHARE` lock on this run row, then resolves the
    # terminal state in the same transaction. The default `FOR UPDATE` conflicts
    # with `FOR KEY SHARE`, so two transitions each holding the share-lock and
    # upgrading here deadlock on the run row. On Postgres/Cockroach we take
    # `FOR NO KEY UPDATE`, which is compatible with `FOR KEY SHARE` (no upgrade
    # cycle) yet still conflicts with itself (concurrent resolutions stay
    # serialized). MySQL has no equivalent mode, so it keeps `FOR UPDATE` and
    # relies on the advancer retrying a deadlock victim; SQLite has no row-level
    # locks, so `lock!` is a no-op there and the deadlock cannot occur.
    def lock_for_terminal_resolution!
      if Ductwork::Record.connection.adapter_name.downcase.match?(/postgresql|cockroach/)
        lock!("FOR NO KEY UPDATE")
      else
        lock!
      end
    end
  end
end
