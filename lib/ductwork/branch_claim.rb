# frozen_string_literal: true

module Ductwork
  class BranchClaim
    def initialize(pipeline_klass)
      @pipeline_klass = pipeline_klass
      @claimed_for_advancing_at = nil
    end

    def latest # rubocop:todo Metrics
      id = Ductwork.wrap_with_app_executor do
        Ductwork::Branch
          .in_progress
          .where(pipeline_klass:, claimed_for_advancing_at:)
          .where(steps: Ductwork::Step.where(status: :advancing))
          .where.not(steps: Ductwork::Step.where.not(status: %w[advancing completed]))
          .order(:last_advanced_at)
          .limit(1)
          .pluck(:id)
          .first
      end

      if id.present?
        transition = nil
        advancement = nil
        now = Time.current

        rows_updated = Ductwork.wrap_with_app_executor do # rubocop:todo Metrics/BlockLength
          Ductwork::Record.transaction do # rubocop:todo Metrics/BlockLength
            branch_claims = Ductwork::Branch
                            .where(id:, claimed_for_advancing_at:)
                            .update_all(claimed_for_advancing_at: now, status: :advancing)

            if branch_claims == 1
              branch = Branch.find(id)
              transition = branch
                           .transitions
                           .where(completed_at: nil)
                           .order(started_at: :desc)
                           .limit(1)
                           .first

              if transition.present?
                attrs = {
                  completed_at: now,
                  error_klass: "Ductwork::ProcessCrash",
                  error_message: "Advancement was abandoned from a process crash",
                }

                transition
                  .advancements
                  .where(completed_at: nil)
                  .order(started_at: :desc)
                  .limit(1)
                  .first
                  &.update!(**attrs)
              else
                transition = branch.transitions.create!(
                  in_step: branch.latest_step,
                  started_at: now
                )
              end

              advancement = transition.advancements.create!(
                process: Ductwork::Process.current,
                started_at: now
              )
            end

            branch_claims
          end
        end

        if rows_updated == 1
          Ductwork.wrap_with_app_executor do
            [
              Ductwork::Branch.find(id),
              transition,
              advancement,
            ]
          end
        else
          Ductwork.logger.debug(
            msg: "Did not claim branch, avoided race condition",
            branch_id: id,
            pipeline_klass: pipeline_klass,
            role: :pipeline_advancer
          )

          nil
        end
      else
        Ductwork.logger.debug(
          msg: "No branches needs advancing",
          pipeline: pipeline_klass,
          role: :pipeline_advancer
        )

        nil
      end
    end

    private

    attr_reader :pipeline_klass, :claimed_for_advancing_at
  end
end
