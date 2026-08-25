# frozen_string_literal: true

module Ductwork
  class Record < ActiveRecord::Base
    self.abstract_class = true

    if Ductwork.configuration.database.present?
      connects_to(database: { writing: Ductwork.configuration.database.to_sym })
    end

    before_create :generate_uuid_v7

    def self.table_name_prefix
      "ductwork_"
    end

    def self.adapter
      connection_db_config.adapter.to_s.downcase
    end

    private

    def generate_uuid_v7
      self.id ||= SecureRandom.uuid_v7
    end
  end
end
