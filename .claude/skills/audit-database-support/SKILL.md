---
name: audit-database-support
description: Audit the OSS ductwork codebase for code, SQL, and migrations that break on a supported database adapter — PostgreSQL, CockroachDB, MySQL 8+, Trilogy, SQLite, or Oracle. Covers SKIP LOCKED and locking-mode differences, RETURNING, upsert syntax, partial indexes, isolation-level divergence, adapter_name detection bugs, type and identifier limits, and support claimed without CI coverage. Use when the user asks about database compatibility, adapter support, cross-database SQL, portability, or whether something works on a specific database.
allowed-tools: Read, Grep, Glob, Bash
---

# Database Support Audit

Audit the OSS ductwork codebase for code and queries that do not work
correctly on every claimed-supported database.

Bash is available for **read-only** inspection. Do not modify files, do not
run migrations, and do not write to any database.

## Step 0 — Load shared context

- `.claude/skills/audit-common/method.md`
- `.claude/skills/audit-common/severity.md`
- `.claude/skills/audit-common/scope-boundaries.md`
- `.claude/skills/audit-common/accepted-tradeoffs.md`

## Supported targets

| Target | Kind | Notes |
|---|---|---|
| PostgreSQL | technology + adapter | Primary target |
| CockroachDB | technology | PG wire protocol, **different semantics** |
| MySQL 8+ | technology | |
| `mysql2` | adapter | |
| Trilogy | adapter | MySQL-compatible, different adapter name |
| SQLite | technology + adapter | Weakest feature set; drives uniformity constraints |
| Oracle | technology + adapter | |

"Supported" means the feature works correctly, not that it fails loudly.
Silent divergence is worse than an exception.

**CI covers only postgres, mysql, trilogy, and sqlite**
(`.github/workflows/main.yml`). Oracle and CockroachDB are claimed with no
automated verification. Auditing that gap is this skill's job — see 3.8.

## Step 1 — Inventory every divergence point

Enumerate and count:

1. **Adapter conditionals** — every `adapter_name` reference in `lib/` and
   `app/`, plus every `postgresql?` / `mysql?` helper call in the migration
   templates.
2. **Raw SQL** — every string passed to `where`, `select_value`, `execute`,
   `lock`, `order`, or built by `DatabaseClock`.
3. **Locking calls** — `lock!`, `with_lock`, `.lock(...)`, any `FOR UPDATE`
   variant.
4. **Upserts** — `upsert`, `upsert_all`, `insert_all`, `unique_by`,
   `RecordNotUnique` rescues.
5. **Migration DDL** — both template directories, especially column types,
   partial indexes, and anything inside an adapter conditional.
6. **Type usage** — UUID columns, JSON columns, boolean columns, text vs
   string, timestamp precision.

## Step 2 — The divergence matrix

Check every inventoried construct against this. This is the substance of the
audit — do not audit from memory of what databases support.

| Feature | PG | Cockroach | MySQL 8+ | SQLite | Oracle |
|---|---|---|---|---|---|
| `FOR UPDATE SKIP LOCKED` | Yes | **Parses, semantics differ** | Yes | **No row locks at all** | Yes |
| `FOR NO KEY UPDATE` | Yes | Yes | **No equivalent** | n/a | **No equivalent** |
| `FOR UPDATE NOWAIT` | Yes | Yes | Yes | n/a | Yes |
| `RETURNING` | Yes | Yes | **No** | 3.35+ | Via different syntax |
| Partial indexes (`WHERE`) | Yes | Yes | **No** | Yes | Via function-based index |
| `ON CONFLICT` target (`unique_by`) | Yes | Yes | **No** (`ON DUPLICATE KEY`, no target) | Yes | **No** (`MERGE`) |
| Native UUID type | Yes | Yes | **No** (string/binary) | **No** | **No** |
| Transactional DDL | Yes | Yes | **No** (implicit commit) | Yes | **No** |
| Default isolation | READ COMMITTED | **SERIALIZABLE** | **REPEATABLE READ** | SERIALIZABLE | READ COMMITTED |
| Advisory locks | Yes | **No** | Yes (`GET_LOCK`) | No | Via `DBMS_LOCK` |
| `LIMIT` in `UPDATE`/`DELETE` | **No** | No | Yes | Compile-flag | **No** |
| Identifier length | 63 | 63+ | 64 | Generous | **30** (128 in 12.2+) |
| Sub-second timestamps | Yes | Yes | Only if precision declared | Text-based | Yes |
| Boolean type | Native | Native | `TINYINT(1)` | Integer | **No** (`NUMBER(1)`) |

Two entries deserve special attention because they fail *silently*:

- **CockroachDB `SKIP LOCKED`.** It is accepted syntactically. Do not
  conclude "it parses, therefore it works." Cockroach's serializable
  isolation and contention handling mean claim behavior is not equivalent to
  Postgres, and its retryable-transaction errors surface differently.
- **MySQL REPEATABLE READ.** A `SELECT` inside a transaction reads a
  snapshot from the transaction's start, not from statement start. A
  select-then-guarded-update CAS therefore behaves differently on MySQL than
  on Postgres — the candidate read can be stale in a way READ COMMITTED
  would not produce. Every CAS claim path needs checking against this.

## Step 3 — Checklist

### 3.1 Adapter detection consistency

The most likely source of real bugs. Every conditional must classify all six
targets correctly.

- **Does the regex cover Cockroach?** The Cockroach adapter reports
  `CockroachDB`, which does **not** match `/postgresql/i`. A helper testing
  `/postgresql/i` sends Cockroach down the non-Postgres branch, while
  `/postgresql|cockroach/` sends it down the Postgres one. Both patterns
  exist in this codebase — that inconsistency means Cockroach gets Postgres
  locking modes but non-Postgres column types. Verify each site and report
  every divergence.
- Does every regex cover both `mysql2` and `Trilogy`?
- Is `downcase` applied consistently, or does one site rely on case-sensitive
  matching that a differently-cased adapter name would miss?
- Does every `case`/`if` chain over adapters have an `else` that **raises**
  rather than silently falling through to a default meant for one adapter?
  Compare against `DatabaseClock`, which raises `NotImplementedError` — that
  is the pattern to hold others to.
- Is detection based on `adapter_name` where a **capability** check would be
  more honest (e.g. SQLite version for `RETURNING`)?

### 3.2 Locking and claiming

- Does each locking construct have a path for every adapter, including SQLite
  where `lock!` is a no-op and row-level locking does not exist?
- Where SQLite has no row locks, what provides the guarantee instead — a CAS
  predicate, or nothing? "SQLite is single-writer so it's fine" is only true
  within one process.
- `FOR NO KEY UPDATE` exists on PG/Cockroach only. Is the fallback for
  MySQL/Oracle correct, and is the deadlock consequence handled (retry) or
  merely accepted?
- Are Cockroach's retryable serialization errors (`40001`) handled anywhere,
  or would they surface as unhandled failures?

### 3.3 Upsert and conflict handling

- `unique_by` requires a conflict target, which MySQL does not accept. Where
  the code branches to `{}` for MySQL, does the resulting
  `ON DUPLICATE KEY UPDATE` match against the intended unique index, or
  against whatever unique key it happens to hit first? This is a silent
  wrong-row hazard, not a syntax error.
- Oracle has neither; does anything reach it?
- Are `RecordNotUnique` rescues adapter-portable — does every adapter raise
  the same ActiveRecord error class for a violated unique index?

### 3.4 Types and identifiers

- UUID: PG gets native `uuid`, others get `string(36)`. Are joins and
  comparisons type-consistent, and does Cockroach land in the right branch?
- Does any code assume the ID column is a native UUID?
- JSON columns: are JSON *operators* used anywhere, or only whole-value
  read/write? Operators are not portable.
- Booleans: does any raw SQL compare against `TRUE`/`FALSE` literals?
- Are any generated identifiers at risk of Oracle's limit? Check the longest
  index and constraint names against the `ductwork_*` table names.

### 3.5 Migrations

- Does every migration run correctly on all six, including the adapter
  conditionals?
- Non-transactional DDL on MySQL and Oracle means a migration that fails
  partway **cannot roll back**. Are multi-statement migrations written so a
  partial application is recoverable?
- Is the `up`/`down` (or `change`) reversible on every adapter?
- Does any migration reference a model class? That breaks when the model
  changes later — flag regardless of adapter.
- Are the install and update templates consistent with each other per
  adapter, or does one branch where the other doesn't?

### 3.6 Raw SQL construction

- Every raw fragment: is the syntax valid on all six, or gated?
- Interpolated values — are they bound parameters or string-interpolated? An
  interpolated integer is portable but still worth flagging if it is ever
  attacker-influenced.
- Are quoting and identifier-escaping done through the connection's quoting
  methods rather than hardcoded backticks or double quotes? Backticks are
  MySQL-only; double quotes mean identifiers on PG and can mean strings
  elsewhere.
- Are functions used that do not exist everywhere (`julianday`,
  `clock_timestamp`, `NUMTODSINTERVAL`, `strftime`, `NOW()`, `GREATEST`)?

### 3.7 ActiveRecord behavior that differs underneath

- Does anything rely on the ordering of an unordered query? Only PG's heap
  ordering makes this appear to work.
- `update_all` / `delete_all` with `LIMIT` — not portable to PG or Oracle.
- Does any code rely on `insert_all` returning IDs? That needs `RETURNING`.
- Does anything depend on autoincrement semantics or last-insert-id?

### 3.8 Claimed support without verification

For each of the six targets, determine and report:

- Is it exercised in CI? Name the workflow job, or state that none exists.
- Is there any spec that exercises the adapter-specific branches written for
  it?
- Are there code paths written for it that no test covers?

**Oracle and CockroachDB currently have no CI coverage.** Report this once,
as a single finding, with the specific untested branches enumerated —
`DatabaseClock`'s Oracle SQL, `run.rb`'s Cockroach locking branch, and any
others found in Step 1. Do not file it separately per branch.

Grade by consequence: an untested branch that would raise on first use is
High; one that merely lacks a regression test is Medium.

## Step 4 — Verify and report

Follow `method.md`. Additionally, every finding must state:

1. **Which adapters are affected** and which are fine.
2. **The failure mode** — does it raise, silently return wrong results, or
   silently degrade? Silent wrongness outranks a raise; say which it is.
3. **Whether the code is reachable** on that adapter, or dead there.
4. **The portable fix**, or an explicitly gated one covering every target.

Do not report a divergence the code already handles correctly — check for an
existing adapter conditional before filing. Per `method.md`, dedupe to the
deepest owning layer: if one helper is wrong for Cockroach, that is one
finding listing its call sites, not one finding per call site.
