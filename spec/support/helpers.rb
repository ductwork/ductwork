# frozen_string_literal: true

module Helpers
  def be_almost_now
    be_within(1.second).of(Time.current)
  end
end
