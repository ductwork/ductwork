# Accepted Tradeoffs — Do Not Report

Each item below has been investigated and consciously decided. Re-reporting
them wastes the reader's attention and buries real findings.

**Do not file these as findings.** If the audit surfaces one, mention it in a
single line under a "Known, previously accepted" heading at the end of the
report — or omit it entirely.

**Exception:** report it *only* if you have genuinely new information — a
concrete interleaving, call site, or consequence not covered by the reasoning
recorded here. If so, lead the finding with what is new. Do not re-argue the
original decision.

---

## 1. Branch claiming does not use `SKIP LOCKED`

Candidate selection (`BranchClaim#find_candidate_branch_id`) joins `Branch` to
`Step`, and SQLite must be supported uniformly (no adapter split like job
claiming's `RowLocking` / `OptimisticLocking` pair). That forced branch
claiming into a universal CAS: `SELECT` a candidate, then a guarded `UPDATE`,
then check rows-updated. Locking across the Branch↔Step join would also
contend with the job-claiming path's own `Step` writes.

Acknowledged 2026-07-22 as a data-model corner, acceptable for now.

**Also accepted:** the resulting thundering herd. With no `SKIP LOCKED` and no
randomization, every advancer thread converges on the same
`ORDER BY last_advanced_at LIMIT 1` row. At ~1M branches this makes the
select→update gap a routine stale window. It costs **wasted claim attempts,
not corruption**. Do not file the contention as a correctness bug.

**Still in force — this rule is auditable:** whatever the candidate `SELECT`
filters on, the claiming `UPDATE` must re-assert. A *new* divergence between
those two predicates is a real finding.

## 2. Layer 3 per-claim heartbeats — rejected for OSS

The plan for `last_progress_at` on Advancement/Execution plus a reaper sweep,
to detect threads that are alive but stuck, was rejected.

Acting on "thread stuck mid-job" means killing the thread, which requires
bounding user-code runtime — that is the step-timeout feature, which is Pro
by design. You cannot distinguish "hung" from "legitimately slow" without it.
The remaining case, a thread hung in *framework* code between claims with no
execution claimed, is rare, short-lived, and holds nothing worth reaping.

Do not re-propose per-claim heartbeats. The OSS durability story is: ensure
blocks plus restart cleanup for thread crashes, process-heartbeat reaper for
process crashes, at-least-once documented for the rest.

## 3. Reaper race 2 (process record drift) — deferred

A reaped-then-resumed process has worker threads holding in-memory ownership
of records that were already released and possibly re-claimed. The worker can
overwrite reaper state and the job can run twice.

Deliberately deferred. Acceptable while Ductwork assumes idempotent jobs. The
fix — an ownership check at the worker's commit boundary — lands when
non-idempotent work does, or if drift is observed in the wild.

Do not file this as Critical double-execution. **At-least-once under process
death is the documented contract.**

Race 1 (the reaper stomping a legitimate concurrent claim) is *not* on this
list — it is an active concern. Note that the design memo proposing
`Advancement#abandon!` / `Availability#abandon!` was superseded: the shipped
mechanism is a claim fence token (`Branch#claim_fence_token`, checked in
`Branch#release!` at `lib/ductwork/models/branch.rb:183`) plus
`BranchClaim#fail_abandoned_advancement`. Audit what is in the tree, not the
memo.

## 4. MySQL durability-spec segfault — deferred

`spec/integration/durability/*` intermittently segfaults on mysql2 only. A
fault-injection `kill` terminates a thread holding a mysql2 connection
mid-query; the C client's fiber-ownership flag is never cleared, the poisoned
connection returns to the pool, and teardown double-frees in libmysqlclient.

Diagnosed as **test isolation, not a production-code bug**. Fix deferred by
explicit decision (2026-06-23) until it shows up often enough in CI to matter.

## 5. No `status` column on transitions or advancements

State is derived from timestamps and error columns by design — in progress is
`completed_at IS NULL`, succeeded adds `error_klass IS NULL`, failed is
`error_klass IS NOT NULL`. Do not propose adding a status enum. Do not report
the derivation as a missing-column problem.

## 6. No `stuck` pipeline state

Considered and rejected. Revival, hooks, dashboards, and transitions do not
diverge between "stuck" and "halted by failure", and a state enum must earn
its place through divergent behavior rather than labeling. Cause metadata
lives on `Branch#halt_reason` instead. Pipeline and Run states stay
`in_progress`, `completed`, `halted`.

## 7. `Ductwork.validate!` is not run at boot

It runs in host-application specs, deliberately, for developer experience. Do
not recommend moving it to boot-time or engine initialization.

---

# Known Open — report only with new information

Not settled, but already on record. Same rule: lead with what is new.

- **`PipelineAdvancer#kill` uses `thread.kill`**, which could poison a mysql2
  connection the same way the spec segfault does, if it ever fires mid-query.
  Flagged as worth a later look; production impact unconfirmed. A finding
  here needs a concrete path showing it firing mid-query.
- **`Ductwork::UserJobError` wrapper.** The rescue layering
  (`Job#execute` owns user code, `JobWorker#work_loop` owns everything else,
  `Branch.with_latest_claimed` owns token-conditional release) would be
  narrower and safer if each layer could rescue by class. Known shape to aim
  for, not implemented. Report only a *new* concrete misrouting it causes.
