# frozen_string_literal: true

module Ductwork
  class Advancement < Ductwork::Record
    belongs_to :process, class_name: "Ductwork::Process", optional: true
    belongs_to :transition, class_name: "Ductwork::Transition"

    validates :started_at, presence: true

    def abandon!
      branch = transition.branch

      Ductwork::Record.transaction do
        branch.lock!
        reload

        return if completed_at.present?

        update!(
          completed_at: Time.current,
          error_klass: "Ductwork::ProcessCrash",
          error_message: "Reaped from orphaned process"
        )
        branch.release!
      end
    end
  end
end
