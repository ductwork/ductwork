# frozen_string_literal: true

module Ductwork
  class SidekiqWrapperJob
    include Sidekiq::Job

    sidekiq_options retry: 0

    def perform(klass, *args)
      return_value = klass.constantize.new.perform(*args)
      job = Job.find_by!(jid: jid)
      job.update!(
        advancing_at: Time.current,
        status: "advancing",
        return_value: return_value
      )
    end
  end
end
