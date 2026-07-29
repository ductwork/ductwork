# frozen_string_literal: true

module Ductwork
  class Advancement < Ductwork::Record
    belongs_to :process, class_name: "Ductwork::Process", optional: true
    belongs_to :transition, class_name: "Ductwork::Transition"

    validates :started_at, presence: true

    CRASH_ERROR_KLASSES = %w[Ductwork::ProcessCrash Ductwork::ThreadCrash].freeze

    def crash?
      CRASH_ERROR_KLASSES.include?(error_klass)
    end

    def process_crashed!
      completed_at = updated_at = Time.current

      Ductwork::Record.transaction do
        rows_updated = self.class
                           .where(id: id, completed_at: nil)
                           .update_all(
                             completed_at: completed_at,
                             updated_at: updated_at,
                             error_klass: "Ductwork::ProcessCrash",
                             error_message: "Reaped from orphaned process"
                           )

        return if rows_updated.zero?

        transition.branch.release!
      end
    end

    def thread_crashed!(expected_token)
      completed_at = updated_at = Time.current

      Ductwork::Record.transaction do
        rows_updated = self.class
                           .where(id: id, completed_at: nil)
                           .update_all(
                             completed_at: completed_at,
                             updated_at: updated_at,
                             error_klass: "Ductwork::ThreadCrash",
                             error_message: "Advancement abandoned from a thread crash"
                           )

        return if rows_updated.zero?

        transition.branch.release!(expected_token)
      end
    end
  end
end
