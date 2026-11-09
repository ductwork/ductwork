# frozen_string_literal: true

module Ductwork
  class StepErrorsController < Ductwork::ApplicationController
    def index
      @error_count = filtered_errors.count
      @step_errors = query_step_errors
      @klasses = Ductwork::Result
                 .failure
                 .joins(execution: { job: :step })
                 .group("ductwork_steps.klass")
                 .pluck("ductwork_steps.klass")
                 .sort
    end

    private

    def query_step_errors
      filtered_errors
        .then(&method(:paginate))
        .includes(execution: { job: { step: :run } })
        .order(created_at: :desc, id: :desc)
    end

    def filtered_errors
      Ductwork::Result.failure.then(&method(:filter_by_step_klass))
    end

    def filter_by_step_klass(relation)
      if params[:klass].present?
        relation
          .joins(execution: { job: :step })
          .where(ductwork_steps: { klass: params[:klass] })
      else
        relation
      end
    end
  end
end
