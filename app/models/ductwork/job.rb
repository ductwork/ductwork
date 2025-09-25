# frozen_string_literal: true

module Ductwork
  class Job < Ductwork::Record
    belongs_to :step, class_name: "Ductwork::Step"

    validates :adapter, presence: true
    validates :enqueued_at, presence: true
    validates :jid, presence: true
    validates :status, presence: true

    enum :status,
         pending: "pending",
         running: "running",
         advancing: "advancing",
         completed: "completed"

    enum :adapter,
         sidekiq: "sidekiq",
         solid_queue: "solid_queue",
         delayed_job: "delayed_job",
         activejob: "activejob"
  end
end
