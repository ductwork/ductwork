# frozen_string_literal: true

module Ductwork
  class Availability < Ductwork::Record
    belongs_to :execution, class_name: "Ductwork::Execution"

    validates :started_at, presence: true
  end
end
