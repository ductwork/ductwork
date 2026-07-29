# frozen_string_literal: true

module Ductwork
  # A work loop exited an iteration with an uncommitted claim without raising
  # a StandardError -- a non-StandardError exception (a signal, Thread#kill),
  # a non-local exit, or a rescue path that itself failed to commit.
  class AbandonedClaim < Ductwork::Crash; end
end
