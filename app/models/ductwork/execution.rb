# frozen_string_literal: true

module Ductwork
  class Execution < Ductwork::Record
    belongs_to :job, class_name: "Ductwork::Job"
    has_one :availability, class_name: "Ductwork::Availability", foreign_key: "execution_id"

    validates :started_at, presence: true
  end
end
