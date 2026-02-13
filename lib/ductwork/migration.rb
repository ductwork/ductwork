# frozen_string_literal: true

module Ductwork
  class Migration < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
    include Ductwork::MigrationHelper
  end
end
