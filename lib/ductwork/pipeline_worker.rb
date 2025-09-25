# frozen_string_literal: true

module Ductwork
  class PipelineWorker
    def initialize(pipeline_name)
      @pipeline_name = pipeline_name
      @running = true
      Signal.trap(:INT) { @running = false }
      Signal.trap(:TERM) { @running = false }
    end

    def run
      while running
        update_pipelines
        sleep(1)
      end
    end

    private

    attr_reader :pipeline_name, :running

    # rubocop:disable Metrics/*
    def update_pipelines
      pipelines.find_each do |pipeline|
        break if !running

        pipeline.steps.in_progress.find_each do |step|
          break if !running

          next_step = step.next_step

          if next_step.collapse? && step.jobs.all?(&:advancing?)
            job = nil

            Record.transaction do
              step.jobs.update!(status: "completed", completed_at: Time.current)
              next_step.update!(status: "in_progress", started_at: Time.current)
              step.update!(status: "completed", completed_at: Time.current)
              job = next_step.jobs.create!(
                adapter: Ductwork.configuration.adapter,
                jid: SecureRandom.uuid,
                enqueued_at: Time.current,
                status: "running"
              )
            end

            # args = [job.step.klass] + step.jobs.pluck(:return_value)

            if job.sidekiq?
              # Ductwork::SidekiqWrapperJob.client_push(
              #   "queue" => Ductwork.configuration.job_queue,
              #   "class" => "Ductwork::SidekiqWrapperJob",
              #   "args" => args,
              #   "jid" => job.jid
              # )
            end
          elsif !next_step.collapse?
            step.jobs.advancing.find_each do |job|
              Record.transaction do
                job.update!(status: "completed", completed_at: Time.current)
                next_step.status = "in_progress"
                next_step.started_at ||= Time.current
                next_step.save!
                # what else?
              end
            end
          end
        end
      end
    end
    # rubocop:enable Metrics/*

    def pipelines
      Ductwork::PipelineInstance.in_progress.where(name: pipeline_name)
    end
  end
end
