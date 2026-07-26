---
name: audit-clock-drift
description: Audit the OSS ductwork codebase for unsafe time handling across hosts — comparing a database timestamp against a Ruby in-memory clock read, measuring durations with a wall clock instead of a monotonic one, timestamp precision mismatches between Ruby and column types, and timezone-naive comparisons. Use when the user asks about clock drift, NTP skew, time comparisons, heartbeat staleness, deadline or timeout correctness, multi-host clock safety, or DatabaseClock usage.
allowed-tools: Read, Grep, Glob, Bash
---

# Clock Drift Audit

Audit the OSS ductwork codebase for time handling that breaks when Ductwork
runs across multiple hosts whose clocks disagree.

Bash is available for **read-only** inspection. Do not modify files.

## Step 0 — Load shared context

- `.claude/skills/audit-common/method.md`
- `.claude/skills/audit-common/severity.md`
- `.claude/skills/audit-common/scope-boundaries.md`
- `.claude/skills/audit-common/accepted-tradeoffs.md`

## The core hazard

Ductwork runs as multiple processes, potentially on multiple hosts, all
against one database. Each host's wall clock drifts independently. Any
comparison that mixes **a timestamp stored by the database** with **a clock
read taken in a Ruby process** is only as correct as the skew between those
two machines.

Under drift these comparisons make healthy work look stale (premature reap,
double execution) or stale work look healthy (never reaped, permanent stall).

`Ductwork::DatabaseClock` exists to resolve exactly this, and it is the
canonical fix for category 1 below. Findings should name it rather than
inventing a remedy.

## Step 1 — Inventory

Enumerate and count before analyzing:

1. Every `Time.current`, `Time.now`, `Time.zone.now`, `Date.today`, and
   `DateTime.now` in `lib/` and `app/`.
2. Every `Ductwork::DatabaseClock` call site (`.now`, `.ago_sql`, `.now_sql`).
3. Every `Process.clock_gettime` call site.
4. Every timestamp column in the migration templates, with its declared
   precision.
5. Every timeout/interval in `lib/ductwork/configuration.rb` and each place
   the value is consumed.

## Step 2 — Classify every time read

Not every `Time.current` is a bug. Most are fine. Sort each call site into
one of these, and only the first three are reportable:

| Class | Reportable? |
|---|---|
| **A. Cross-host comparison** — Ruby clock read compared against a DB-stored timestamp, gating a safety or visibility decision | **Yes** — usually High/Critical |
| **B. Wall-clock duration** — elapsed time or a deadline measured by subtracting/adding wall-clock reads | **Yes** — usually Medium/High |
| **C. Precision or timezone mismatch** — read and column disagree on resolution or zone | **Yes** — usually Medium |
| D. Same-process comparison — both reads from one process's clock, used only for that process's own bookkeeping | No, unless it's also class B |
| E. Recorded value — a timestamp written for display, audit, or metrics, never compared to gate a decision | No |
| F. Test/factory/dashboard code | No |

Class D is the common false positive: comparing two in-memory reads inside
one process is drift-safe by construction, because there is only one clock.
It may still be a class B bug if the interval matters. Check for that, then
move on — do not file it as drift.

## Step 3 — Checklist

### 3.1 Cross-host comparison (class A)

The critical category. For each, ask: does one side of this comparison come
from the database and the other from Ruby?

Highest-risk surfaces — check each explicitly:

- **Heartbeat staleness.** Comparing `last_heartbeat_at` (written by process
  A) against a clock read in process B decides whether to reap A. Drift here
  reaps live processes or leaves dead ones running.
- **Claim eligibility.** Any `WHERE ... <= ?` where the bind is a Ruby time
  and the column is DB-written — including retry-after / backoff gates and
  availability windows.
- **Reap sweeps and global timeouts.** "Started more than N seconds ago"
  predicates.
- **Ordering.** `ORDER BY` on a column written by many hosts is already
  approximate; a finding here needs a real consequence, not just imprecision.

**Fix:** push the comparison into SQL so both sides resolve on the database
server — `DatabaseClock.ago_sql(column, interval)` for "older than N
seconds", `DatabaseClock.now_sql(column)` for "at or before now". Where a
materialized value must be written, use `DatabaseClock.now` so the value
originates from the same clock everything compares against.

**Also check the writes.** Storing `Time.current` into a column that another
host later compares against the DB clock reintroduces the skew from the write
side. Both ends must agree on which clock is authoritative.

### 3.2 Monotonic vs wall clock (class B)

A distinct bug from drift, and easy to miss because it is single-host. Wall
clocks step — NTP corrections, DST, manual sets, VM resume. A duration or
deadline computed from wall-clock reads can jump backward or forward
arbitrarily.

Check every:

- `deadline = Time.current + timeout`, then `while Time.current < deadline`
- `(Time.current - some_earlier_read) > threshold`
- Shutdown budgets, kill budgets, poll loops, backoff computation

**Fix:** `Process.clock_gettime(Process::CLOCK_MONOTONIC)` for anything
measuring *elapsed* time. Wall clock is correct only for timestamps that must
be meaningful to a human or comparable across processes.

Note the asymmetry when reporting: for a shutdown budget a backward clock
step means the loop waits far too long; for a staleness threshold it means
the check never fires. Say which.

The codebase already uses `CLOCK_MONOTONIC` in at least one place — cite it
as the in-repo precedent so the fix reads as consistency, not novelty.

### 3.3 Precision and truncation (class C)

- Do timestamp columns declare a precision, and does it match what the code
  compares against? `DatabaseClock` emits `CURRENT_TIMESTAMP(6)` on
  MySQL/Trilogy — microseconds. A MySQL `DATETIME` declared with no precision
  stores **whole seconds** and truncates on write. A stored value can then
  appear up to a second *earlier* than it was, making `<=` comparisons fire
  early or late near the boundary.
- SQLite stores timestamps as strings; `julianday()` comparison and string
  comparison do not order identically for mixed formats.
- Does Ruby write sub-second precision the column cannot hold?
- Are two columns compared against each other stored at different precisions?

Grade these by whether the truncation can cross a decision boundary. If the
threshold is 60 seconds, a one-second truncation is Low. If a claim gate
compares near-simultaneous timestamps, it is not.

### 3.4 Timezone handling

- `Time.now` (system zone) rather than `Time.current` (app zone) — a real bug
  when hosts have different `TZ`.
- Comparing a zone-aware value to a naive one.
- `Date.today` in any gating logic — it's the system zone and it rolls over
  at different instants per host.

### 3.5 The single-clock assumption

`DatabaseClock` is only safe if every process reaches the *same* clock.
Verify and report where it does not hold:

- A read replica serves a different `clock_timestamp()` than the primary. Are
  any of these comparisons on a connection that could be routed to a replica?
- CockroachDB is multi-node; its clock guarantees differ from single-primary
  Postgres. Does anything assume tighter ordering than Cockroach provides?
- Does `DatabaseClock` handle every supported adapter, and does the `else`
  branch raise rather than silently falling back? An adapter that reaches the
  fallback would be comparing against nothing.

## Step 4 — Verify and report

Follow `method.md`. Additionally, for each finding state **which two clocks
are being compared** and **which direction of skew causes which failure**.
A clock finding without that is not actionable:

> `process.rb:NN` compares `last_heartbeat_at` (written by the worker host)
> against `Time.current` on the supervisor host. If the supervisor's clock
> runs fast by more than the timeout, live workers are reaped and their
> in-flight work is re-claimed while still running.

Per `severity.md`, cross-host comparisons that gate reaping or claiming are
High or Critical because the failure is silent double execution or a
permanent stall. Recorded-but-uncompared timestamps are not findings.
