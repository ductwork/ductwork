# frozen_string_literal: true

module Ductwork
  class Availability < Ductwork::Record
    belongs_to :execution, class_name: "Ductwork::Execution"
    belongs_to :process, class_name: "Ductwork::Process", optional: true

    validates :started_at, presence: true
    validates :pipeline_klass, presence: true

    # NOTE: this method is essentially the middleman antipattern, but we keep
    # it for symmetry with `Ductwork::Advancement#abandon!`
    def abandon!
      execution.crashed!
    end
  end
end
