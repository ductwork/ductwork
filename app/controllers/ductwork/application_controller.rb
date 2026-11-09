# frozen_string_literal: true

module Ductwork
  class ApplicationController < ActionController::Base
    DEFAULT_PER_PAGE = 50

    helper_method :current_page, :per_page

    def query_pipeline_runs
      filtered_runs
        .then(&method(:paginate))
        .order(started_at: :desc, id: :desc)
    end

    def filtered_runs
      runs_of_klass.then(&method(:filter_by_status))
    end

    def runs_of_klass
      Ductwork::Run.all.then(&method(:filter_by_klass))
    end

    def filter_by_klass(relation)
      if params[:klass].present?
        relation.where(pipeline_klass: params[:klass])
      else
        relation
      end
    end

    def filter_by_status(relation)
      if params[:status].present?
        relation.where(status: params[:status])
      else
        relation
      end
    end

    def paginate(relation)
      relation.limit(per_page).offset(current_page * per_page)
    end

    def per_page
      @per_page || DEFAULT_PER_PAGE
    end

    def current_page
      [params[:page].to_i, 0].max
    end

    def error_counts(run_ids)
      Ductwork::Result
        .failure
        .joins(execution: { job: :step })
        .where(ductwork_steps: { run_id: run_ids })
        .group("ductwork_steps.run_id")
        .count
    end

    def halt_reasons(run_ids)
      Ductwork::Branch
        .where(run_id: run_ids, status: "halted")
        .group(:run_id, :halt_reason)
        .count
        .each_with_object({}) do |((run_id, reason), count), reasons|
          (reasons[run_id] ||= {})[reason] = count
        end
    end
  end
end
