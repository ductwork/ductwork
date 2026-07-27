# frozen_string_literal: true

module Ductwork
  # NOTE: pollers start in lockstep and stay there. A runner spawns its
  # advancer (or worker) threads in a tight loop, so they all reach their first
  # idle `sleep` within microseconds of each other, and because every
  # subsequent sleep is the same fixed interval the phase alignment never
  # decays on its own. Aligned pollers wake together, run the same candidate
  # `SELECT` against the same rows, and all but one lose the claim race -- the
  # very contention that sampling a candidate window in `BranchClaim` is meant
  # to spread out. Spreading the wake-ups spreads the queries.
  #
  # The jitter is re-rolled on every sleep rather than being a per-thread
  # offset chosen once at startup, because a burst of work re-synchronizes the
  # pollers no matter how they were staggered: they all stay busy while the
  # queue drains and then all go idle together the moment it empties.
  #
  # The spread is symmetric so the configured polling timeout stays the average
  # wait. Someone who sets `polling_timeout: 1` still gets a one second average
  # poll latency instead of a quietly slower one.
  module PollingInterval
    JITTER_RATIO = 0.25

    def self.jittered(timeout)
      spread = timeout * JITTER_RATIO

      timeout + Kernel.rand(-spread..spread)
    end
  end
end
