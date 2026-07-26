# Audit Scope & Boundaries

## The OSS / Pro line

This repo is the OSS `ductwork` gem (LGPL v3). A paid `ductwork-pro` gem
extends it via `prepend`. **Pro features are not gaps in OSS.** They are
deliberately absent.

An audit that recommends a Pro feature as the fix for an OSS finding is
producing noise, and it is the single most common failure mode of the
durability and reliability audits in particular.

### In OSS — fair game to audit

- Core transitions: `chain`, `expand`, `divide`, `divert`, `combine`,
  `converge`, `collapse`
- Core pipeline DSL
- Two-phase commit (transition + advancement records) for advancement
- Supervisor / advancer / worker process hierarchy
- Forking and threaded concurrency modes
- Configurable advancer thread pool
- Heartbeat-based orphan detection
- SKIP LOCKED claiming with atomic `UPDATE...WHERE` fallback
- Reaper with global-timeout sweeps
- Restart of worker threads stuck in *framework* code (no execution claimed)
- `Ductwork::Pipeline#revive!`
- UUID v7 primary keys across PG / MySQL / SQLite
- Rails engine-mountable web dashboard

### In Pro — do NOT recommend, do NOT report as missing

- Human-in-the-loop / the `dampen` transition
- **Step timeouts** defined in the DSL
- **Step delays** defined in the DSL
- Restart of worker threads stuck *inside job execution* (a claimed execution
  that will not return) — this requires bounding user-code runtime, which is
  the step-timeout feature
- Large payload support
- Resumable batched fan-out / fan-in
- Interruptible pipeline advancement
- StatsD metric reporting

### Hard rules

- Never reference `Ductwork::Pro::*` constants from OSS code, and never
  suggest that OSS code do so.
- OSS must remain fully functional standalone. A finding whose fix requires
  Pro is not a valid OSS finding.
- If the correct fix genuinely lies in Pro, say so in one line and move on.
  Do not file it.

## Supported databases

Claimed support, per `CLAUDE.md` and the install migration templates:

| Adapter | Notes |
|---|---|
| PostgreSQL | Primary target |
| CockroachDB | PG wire protocol, divergent semantics |
| MySQL 8+ | Both the technology and the `mysql2` adapter |
| Trilogy | MySQL-compatible adapter |
| SQLite | No partial-index-free workarounds; drives "uniformity" constraints |
| Oracle | |

**CI covers only postgres, mysql, trilogy, and sqlite**
(`.github/workflows/main.yml`). Oracle and CockroachDB are claimed as
supported with no automated coverage. Claimed-but-untested support is itself
a legitimate finding for `audit-database-support` — flag it there, not in
every audit.

## Code layout

- `lib/ductwork/` — core: claiming, clock, config, context, fault injection
- `lib/ductwork/models/` — ActiveRecord models (the durability surface)
- `lib/ductwork/processes/` — supervisor / advancer / worker hierarchy and
  their runners
- `lib/ductwork/dsl/` — pipeline definition DSL
- `lib/generators/ductwork/install/templates/db/` — install migrations
- `lib/generators/ductwork/update/templates/db/` — **upgrade migrations**
- `app/` — the mountable dashboard engine
- `spec/integration/durability/` — fault-injection crash-window specs

**Schema changes land in two places.** A new index or column must be added to
the install template *and* as a new upgrade migration, or existing
installations never receive it. An audit that recommends a schema change
without noting both is incomplete.

## Key abstractions to prefer in fixes

When recommending a fix, name the existing primitive rather than inventing a
new one:

- `Ductwork::DatabaseClock` — `.now`, `.ago_sql`, `.now_sql`. The canonical
  answer to any cross-host time comparison.
- `Ductwork::BranchClaim` — branch claiming CAS.
- `Ductwork::RowLockingExecutionClaim` / `OptimisticLockingExecutionClaim` —
  the adapter-split job claim strategies.
- `Ductwork::FaultInjection.checkpoint(:name)` — named crash points, driven
  by the `DUCTWORK_FAULT` env var.
- `Ductwork::MigrationHelper` — adapter capability predicates for migrations.
- `Ductwork::Step::ADVANCEABLE_STATUSES` — the shared advanceable predicate.
