# frozen_string_literal: true

module Ductwork
  class Result < Ductwork::Record
    belongs_to :execution, class_name: "Ductwork::Execution"

    validates :result_type, presence: true

    enum :result_type,
         success: "success",
         failure: "failure",
         timed_out: "timed_out"
  end
end
