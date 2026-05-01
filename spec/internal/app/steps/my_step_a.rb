# frozen_string_literal: true

class MyStepA < Ductwork::Step
  def initialize(*); end

  def execute
    "return_value"
  end
end
