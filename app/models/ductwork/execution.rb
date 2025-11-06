# frozen_string_literal: true

module Ductwork
  class Execution < Ductwork::Record
    belongs_to :job, class_name: "Ductwork::Job"
    has_one :availability, class_name: "Ductwork::Availability", foreign_key: "execution_id"
    has_one :run, class_name: "Ductwork::Run", foreign_key: "execution_id"
    has_one :result, class_name: "Ductwork::Result", foreign_key: "execution_id"

    validates :retry_count, presence: true
    validates :started_at, presence: true
  end
end
