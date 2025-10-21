# frozen_string_literal: true

module Ductwork
  class ReadyJob < Ductwork::Record
    belongs_to :job, class_name: "Ductwork::Job"
  end
end
