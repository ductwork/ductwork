# frozen_string_literal: true

module Ductwork
  class Record < ActiveRecord::Base
    self.abstract_class = true

    if Ductwork.configuration.database.present?
      connects_to(database: { writing: Ductwork.configuration.database.to_sym })
    end

    def self.table_name_prefix
      "ductwork_"
    end
  end
end
