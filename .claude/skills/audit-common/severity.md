# Severity Rubric

Ductwork is a job pipeline framework. Severity is graded by **what the user's
pipeline does wrong**, not by how unusual the code looks. A framework bug
silently corrupts every host application that hits it, so correctness
outranks performance at every level.

## Critical

Silent incorrectness or permanent loss. The host application cannot detect it
and cannot recover without manual intervention.

- Work is lost: a step reports success but its result is never durably
  written, or a branch is dropped and never advanced.
- Double execution of a non-idempotent unit under a realistic interleaving,
  where at-least-once is not the documented contract for that path.
- A pipeline stalls forever with no reaper, timeout, or revive path that can
  recover it.
- Data corruption: a run reaches a terminal state that contradicts its
  branches, or a completed run overwritten as halted (or the reverse).
- A migration that can lose or corrupt existing rows.

## High

Recoverable but requires operator action, or a correctness bug that needs an
uncommon-but-real interleaving.

- Stuck work that the reaper recovers only after a global timeout, when a
  targeted mechanism should have caught it promptly.
- A crash window that leaks a claim, requiring a reap sweep to clear.
- A race that needs specific timing to trigger but produces incorrect state
  when it does.
- Missing index on a hot claim path that degrades throughput non-linearly
  with table size.
- An adapter in the supported list where a code path raises or silently
  misbehaves.

## Medium

Degraded behavior with a clear operational signal, or a latent bug that today
is masked by an assumption that holds but is not enforced.

- Correctness that depends on an invariant no constraint or guard enforces.
- Error routing that sends a failure to the wrong recovery path, where the
  outcome is still eventually correct but the retry accounting is wrong.
- Missing index on a warm path.
- Adapter support that works but relies on undocumented or version-specific
  behavior.
- A crash window that is real but leaks only a recoverable record with no
  correctness consequence.

## Low

Correct today and correct under the interleavings that matter, but fragile to
future change.

- Duplicated logic where one copy could drift from another (notably: a
  predicate expressed in two places that must stay in sync).
- Missing test coverage for a durability window that is otherwise sound.
- Naming or structure that invites a future contributor to introduce a real
  bug.

Do not file style, formatting, or preference items at any severity. Rubocop
owns those.

## Grading rules

- **Grade by outcome, not by mechanism.** "No lock here" is not a finding.
  "Two advancers both pass this check and both create an advancement, so the
  step runs twice" is a finding.
- **If you cannot describe the interleaving, it is not High or Critical.**
  A finding whose "why it matters" is theoretical caps at Medium.
- **A documented, accepted contract is not a bug.** At-least-once execution
  under process death is Ductwork's documented contract. Do not file it as
  Critical double-execution. See `accepted-tradeoffs.md`.
- **Frequency does not raise severity; consequence does.** A rare path that
  silently loses data outranks a common path that wastes a claim attempt.
