# frozen_string_literal: true

require "ductwork/testing/helpers"

module Ductwork
  module Testing
    if defined?(RSpec)
      require "ductwork/testing/rspec"
    elsif defined?(Minitest)
      require "ductwork/testing/minitest"
    else
      raise "Testing framework is not supported"
    end
  end
end
