# frozen_string_literal: true

module Ductwork
  class Record < ActiveRecord::Base
    self.abstract_class = true

    def self.table_name_prefix
      "ductwork_"
    end
  end
end
