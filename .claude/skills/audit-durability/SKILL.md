---
name: audit-durability
description: Audit the OSS ductwork codebase for durability gaps — crash windows where a process or thread death leaks a claim, loses work, or stalls a pipeline; incorrect transaction boundaries; incomplete claim fencing; reaper races; error-routing mistakes; and liveness holes where a run can never reach a terminal state. Use when the user asks to audit durability, crash safety, reliability, at-least-once behavior, reap correctness, claim leaks, stuck pipelines, or "what happens if this crashes here".
allowed-tools: Read, Grep, Glob, Bash
---

# Durability Audit

Audit the OSS ductwork codebase for durability gaps.

Bash is available for **read-only** inspection (`grep`, `git log`, `git
blame`, listing files). Do not modify any file, do not run the test suite,
and do not run migrations.

## Step 0 — Load shared context

Read these first. They are not optional; they define what counts as a
finding.

- `.claude/skills/audit-common/method.md` — inventory, verification, output
- `.claude/skills/audit-common/severity.md` — how to grade
- `.claude/skills/audit-common/scope-boundaries.md` — OSS/Pro line, layout
- `.claude/skills/audit-common/accepted-tradeoffs.md` — do not re-report

**The Pro boundary matters most in this audit.** Step timeouts, interruptible
advancement, and restarting threads stuck *inside job execution* are Pro
features. They are the natural-sounding fix for several things you will find.
They are out of scope. See `scope-boundaries.md`.

## Step 1 — Inventory the durability surface

Enumerate and count each of these before analyzing. State the counts in the
report.

1. **Claim paths** — `lib/ductwork/branch_claim.rb`,
   `execution_claim.rb`, `row_locking_execution_claim.rb`,
   `optimistic_locking_execution_claim.rb`.
2. **Multi-step state mutations** — every method that writes more than one
   row, or writes a row and then acts on it. Concentrated in
   `lib/ductwork/models/` (`branch.rb`, `advancement.rb`, `execution.rb`,
   `job.rb`, `run.rb`, `step.rb`, `process.rb`).
3. **Transaction boundaries** — every `transaction do`, `after_commit`,
   `lock!`, and `with_lock`.
4. **Rescue and ensure sites** — every `rescue` and `ensure` in `lib/`.
5. **Process and thread lifecycle** — all of `lib/ductwork/processes/`:
   supervisors, runners, `job_worker.rb`, `pipeline_advancer.rb`, and their
   start/restart/kill/shutdown paths.
6. **Heartbeat and reap paths** — `Process.report_heartbeat!`,
   `Process#reap!`, and each `reap_process_record!` across the runners and
   supervisors.
7. **Existing fault-injection checkpoints** — `grep -rn
   "FaultInjection.checkpoint" lib/` and the specs in
   `spec/integration/durability/`.

## Step 2 — Crash-window analysis (the core of this audit)

This is the primary technique. Do this before the checklist in Step 3.

For every multi-step operation on the inventory, enumerate the points between
its steps and answer, at each point:

> If the process is SIGKILLed here — or the thread is killed here, or the
> database connection drops here — what state is left behind, and what
> recovers it?

For each window, name the recovery mechanism explicitly:

- An `ensure` block (does it actually run for this kind of death? `ensure`
  runs on `Thread#kill` and `Interrupt`; it does **not** run on `SIGKILL`,
  `exit!`, or a segfault)
- Transaction rollback (only if the writes are genuinely in one transaction)
- The heartbeat reaper (recovers on the *next sweep* — note the latency)
- A CAS predicate that makes a stale write a no-op
- The claim fence token (`Branch#claim_fence_token`, checked in
  `Branch#release!`)
- `BranchClaim#fail_abandoned_advancement`, reactively on next claim
- Nothing — **this is the finding**

A window whose only recovery is "the reaper eventually" is not automatically
a bug; that is the design for process death. It *is* a bug when the reaper
cannot see the leaked state, when recovery requires the global timeout for
something that should be caught promptly, or when the leaked state blocks
other work in the meantime.

Report the specific window, not the general concern:

> Between the `UPDATE` at `branch_claim.rb:NN` and the advancement `INSERT`
> at `:MM`, a SIGKILL leaves the branch claimed with no advancement row.
> Recovery is X, which takes Y.

## Step 3 — Checklist

Work these in order. For each, cite file:line or state that the category came
back clean.

### 3.1 Write ordering and observable side effects

- Is state written durably **before** the action it authorizes, or after?
- Does anything become visible to another process before the transaction that
  makes it correct has committed?
- Are results written before the record that says the work is done?
- Is a job enqueued or a branch made claimable inside a transaction that can
  still roll back?

### 3.2 Transaction boundaries

- Does each `transaction do` span exactly the writes that must be atomic —
  no more, no less?
- Are there nested transactions where an inner rollback silently becomes a
  savepoint rollback, leaving the outer one committed?
- Is there external or long-running work (a network call, user code, a sleep)
  inside a transaction, holding locks?
- Does anything rely on `after_commit` ordering that is not guaranteed?
- Does a `lock!` happen *before* the read whose value it protects, or after
  (a lock taken after reading protects nothing — check for a `reload`)?

### 3.3 Claim integrity and fencing

- **The re-assertion rule:** whatever the candidate `SELECT` filters on, the
  claiming `UPDATE` must re-assert. A divergence between the two predicates
  is a real finding. `Ductwork::Step::ADVANCEABLE_STATUSES` is the shared
  constant; check both sides still use it.
- Is `rows_updated` checked after every CAS `UPDATE`, and is losing the CAS
  handled as a normal outcome rather than an error?
- Can a claim be released by someone who no longer owns it — is the fence
  token compared on every release path?
- Can the same unit of work be claimed twice concurrently?
- Is `process_id` (or the fence token) verified before a terminal write, or
  is the write blind?

### 3.4 Reaper correctness

- Can the reaper release a claim that a healthy worker legitimately re-took
  between the staleness check and the release? (Race 1 — active concern.)
- Does every reap path go through the same guarded release, or does one
  open-code it?
- Is the heartbeat written on a schedule that cannot be starved by the work
  loop itself — can a long unit of work delay the heartbeat past the timeout
  and cause a self-reap?
- Are reap sweeps idempotent if two supervisors sweep concurrently?
- Are crash/recovery counters incremented exactly once per event?

Race 2 (zombie worker overwriting reaper state) is deferred by decision — see
`accepted-tradeoffs.md`.

### 3.5 Thread and process lifecycle

- Does every thread body have an outer `ensure` that abandons in-flight work?
- Does thread *restart* clean up what the dead thread held, for deaths that
  bypass `ensure`?
- Is `restart` genuinely distinct from `start`, or aliased such that cleanup
  is skipped?
- On SIGTERM, is there a drain path — does in-flight work finish or get
  cleanly abandoned, or is it simply dropped?
- Does a `thread.kill` risk interrupting a query mid-flight and poisoning the
  connection? (Known open for `PipelineAdvancer#kill` — new information only.)
- If the supervisor restarts, does the sweep catch records orphaned by the
  children it lost?

### 3.6 Error routing and rescue layering

The three legitimate layers, each owning exactly one semantic class:

| Layer | Owns |
|---|---|
| `Job#execute` | user code raising → errored (retry) |
| `JobWorker#work_loop` | anything else raising → crashed (keep thread alive) |
| `Branch.with_latest_claimed` | token-conditional release on any exit |

- Does any `rescue` extend past its layer's boundary call to cover framework
  bookkeeping? A DB error while *recording success* must not route to the
  user-code-failed path — it belongs to the outer backstop.
- Can one logical failure produce two retry records by passing through two
  layers?
- Does any `rescue` swallow an error without recording it, leaving a claim
  held and a record neither completed nor failed?
- Are retry and crash counters attributed to the right layer?

### 3.7 Liveness and terminal-state resolution

- Can a run sit `in_progress` forever with no work left? Check fan-in
  (`combine`, `collapse`, `converge`) where the last sibling to finish must
  trigger resolution.
- Is `resolve_terminal_state!` reached on **both** the halt path and the
  completion path?
- Are terminal transitions guarded by a run lock plus an already-terminal
  check, so a completed run cannot be overwritten as halted or vice versa?
- Can a fan-in wait on a sibling that will never reach a terminal state?
- Do claims exclude halted and completed runs, so orphaned work cannot
  resurrect a finished pipeline?
- Is every `halt_reason` path reachable, and does each caller put the step in
  its correct terminal state *before* halting?

### 3.8 Connection and database failure

- What happens if the connection drops mid-transaction — is the in-memory
  record state now a lie about what is committed?
- Does a failed heartbeat write retry, or silently pass and let the process
  be reaped while healthy?
- Are claim queries safe to retry, or would a retry after an ambiguous
  timeout double-claim?

## Step 4 — Fault-injection coverage cross-check

Ductwork has a named-checkpoint fault harness
(`lib/ductwork/fault_injection.rb`, driven by `DUCTWORK_FAULT`, supporting
`kill`, `raise`, `sleep`, `exit`), with crash-window specs in
`spec/integration/durability/`.

Cross-reference the crash windows found in Step 2 against the checkpoints
that exist and the specs that exercise them. Report:

- **Windows with no checkpoint** — a durability-critical window that cannot
  currently be tested. Recommend the checkpoint name and where it goes.
- **Checkpoints with no spec** — injection points nothing exercises.
- **Windows covered only for one failure mode** — e.g. a `raise` spec but no
  `kill` spec, when `ensure` behavior differs between them. This distinction
  is the whole point of the harness.

Coverage gaps are usually Medium — real, but not themselves a live bug.
Grade Higher only when the uncovered window is one you independently found a
correctness problem in.

## Step 5 — Verify and report

Follow `method.md`: re-read every cited `file:line`, drop what does not hold
or is already accepted, deduplicate to the deepest owning layer, and report
inline in the format specified there.

Findings in this audit must name the interleaving. "This is not locked" is
not a finding; "advancer A passes the check at :NN while advancer B is
between :MM and :QQ, so both create an advancement and the step runs twice"
is a finding. Per `severity.md`, a finding with no describable interleaving
caps at Medium.
