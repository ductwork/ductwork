# frozen_string_literal: true

module Helpers
  def be_almost_now
    be_within(3.seconds).of(Time.current)
  end
end
