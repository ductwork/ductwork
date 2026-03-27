# frozen_string_literal: true

module Ductwork
  class Advancement < Ductwork::Record
    belongs_to :process, class_name: "Ductwork::Process", optional: true
    belongs_to :transition, class_name: "Ductwork::Transition"

    validates :started_at, presence: true
  end
end
