# frozen_string_literal: true

module Ductwork
  class Engine < ::Rails::Engine
    initializer "ductwork.load_configuration" do
      path = Rails.root.join("config/ductwork.yml")
      Ductwork.configuration ||= Configuration.new(path: path)
    end
  end
end
