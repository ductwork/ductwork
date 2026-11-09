# frozen_string_literal: true

module Ductwork
  class PipelinesController < Ductwork::ApplicationController
    def index
      @run_count = filtered_runs.count
      @status_counts = runs_of_klass.group(:status).count
      @runs = query_pipeline_runs
      @error_counts = error_counts(@runs.map(&:id))
      @klasses = Ductwork::Pipeline.group(:klass).pluck(:klass).sort
      @statuses = Ductwork::Pipeline.statuses.keys
    end

    def show
      @per_page = 25
      @pipeline = Ductwork::Pipeline.find(params[:id])
      @last_run = @pipeline.runs.order(started_at: :desc).first
      @run_count = @pipeline.runs.count
      @graph = Ductwork::PipelineGraph.new(@last_run)
      @error_count = error_counts([@last_run.id]).fetch(@last_run.id, 0)
      @halts = halt_reasons([@last_run.id]).fetch(@last_run.id, {})
      load_steps
    end

    private

    def load_steps
      @status_counts = steps_in_scope.group(:status).count
      @step_total = @last_run.steps.count
      @step_count = filtered_steps.count
      @steps = query_steps
      @klasses = @last_run.steps.group(:klass).pluck(:klass).sort
      @nodes = @last_run.steps.group(:node).pluck(:node).sort
      @statuses = Ductwork::Step.statuses.keys
    end

    def query_steps
      filtered_steps
        .includes(job: { executions: %i[availability attempt result] })
        .then(&method(:paginate))
        .order(:started_at, :id)
    end

    def filtered_steps
      steps_in_scope.then(&method(:filter_by_status))
    end

    def steps_in_scope
      @last_run
        .steps
        .then(&method(:filter_by_step_klass))
        .then(&method(:filter_by_node))
    end

    def filter_by_step_klass(relation)
      if params[:klass].present?
        relation.where(klass: params[:klass])
      else
        relation
      end
    end

    def filter_by_node(relation)
      if params[:node].present?
        relation.where(node: params[:node])
      else
        relation
      end
    end
  end
end
