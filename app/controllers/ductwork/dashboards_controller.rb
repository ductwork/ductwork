# frozen_string_literal: true

module Ductwork
  class DashboardsController < Ductwork::ApplicationController
    RECENT_RUNS = 10
    HALTED_RUNS = 5

    def show
      @metrics = metrics
      @halted_runs = Ductwork::Run
                     .halted
                     .where(pipeline_id: Ductwork::Pipeline.halted.select(:id))
                     .order(halted_at: :desc, id: :desc)
                     .limit(HALTED_RUNS)
      @halts = halt_reasons(@halted_runs.map(&:id))
      @class_summaries = class_summaries
      @runs = Ductwork::Run.order(started_at: :desc, id: :desc).limit(RECENT_RUNS)
      @error_counts = error_counts(@runs.map(&:id))
    end

    private

    def metrics
      Ductwork::Pipeline
        .group(:status)
        .count
        .slice("completed", "in_progress", "halted")
        .with_indifferent_access
        .reverse_merge(completed: 0, in_progress: 0, halted: 0)
        .merge(step_errors: Ductwork::Result.failure.count)
    end

    def class_summaries
      last_started_at = Ductwork::Run.group(:pipeline_klass).maximum(:started_at)
      counts = Ductwork::Pipeline.group(:klass, :status).count

      counts.keys.map(&:first).uniq.sort.map do |klass|
        total = counts.sum { |(key, _), count| key == klass ? count : 0 }
        halted = counts.fetch([klass, "halted"], 0)
        completed = counts.fetch([klass, "completed"], 0)

        {
          klass: klass,
          active: total - halted - completed,
          halted: halted,
          completed: completed,
          last_started_at: last_started_at[klass],
        }
      end
    end
  end
end
