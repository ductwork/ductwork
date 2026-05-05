# frozen_string_literal: true

module Ductwork
  class Advancement < Ductwork::Record
    belongs_to :process, class_name: "Ductwork::Process", optional: true
    belongs_to :transition, class_name: "Ductwork::Transition"

    validates :started_at, presence: true

    def abandon!
      Ductwork::Record.transaction do
        rows_updated = self.class
                           .where(id: id, completed_at: nil)
                           .update_all(
                             completed_at: Time.current,
                             error_klass: "Ductwork::ProcessCrash",
                             error_message: "Reaped from orphaned process"
                           )

        return if rows_updated.zero?

        transition.branch.release!
      end
    end
  end
end
