---
name: audit-database-indexes
description: Audit the OSS ductwork codebase for missing, unusable, or redundant database indexes — hot claim-path queries with no supporting index, composite indexes in the wrong column order, partial-index predicates that break on MySQL, foreign keys and polymorphic columns without coverage, and indexes that duplicate a prefix of another. Use when the user asks about missing indexes, slow queries, query plans, index coverage, schema performance, or scaling a table.
allowed-tools: Read, Grep, Glob, Bash
---

# Database Index Audit

Audit the OSS ductwork codebase for queries whose access pattern is not
supported by an index, and for indexes that cost writes without earning it.

Bash is available for **read-only** inspection. Do not modify files, do not
run migrations, and do not write to any database.

## Step 0 — Load shared context

- `.claude/skills/audit-common/method.md`
- `.claude/skills/audit-common/severity.md`
- `.claude/skills/audit-common/scope-boundaries.md`
- `.claude/skills/audit-common/accepted-tradeoffs.md`

**Both migration directories are in scope:**

- `lib/generators/ductwork/install/templates/db/` — fresh installs
- `lib/generators/ductwork/update/templates/db/` — existing installations

An index added only to the install template never reaches anyone who already
runs Ductwork. **Every index recommendation must specify both**: the change
to the install template *and* a new upgrade migration. A recommendation that
names only one is incomplete and should be reported as such.

## Step 1 — Build two inventories

### 1a. The index inventory

Read every migration in both directories. Produce a table of what an
already-migrated installation actually has: table, columns in order, unique?,
partial predicate?, and which adapters receive it (several indexes are inside
`if mysql?` / `else` branches and differ per adapter).

Watch for indexes added, renamed, or dropped by later upgrade migrations —
the install template alone does not tell you the current shape.

### 1b. The query inventory

Enumerate every query in `lib/` and `app/`. Do not rely on grep for `where`
alone; include:

- Named scopes and class-method finders on the models
- `where`, `order`, `limit`, `pluck`, `exists?`, `find_each`, `update_all`,
  `delete_all`, `count`
- The claim paths in `branch_claim.rb`, `row_locking_execution_claim.rb`,
  `optimistic_locking_execution_claim.rb`
- Raw SQL fragments, including those built by `DatabaseClock`
- Association traversals that emit a query per parent
- Dashboard queries in `app/` — different profile from the hot path, still
  real

For each query record: table, `WHERE` columns, `ORDER BY`, `LIMIT`, and
whether it runs on a hot path.

## Step 2 — Classify by heat

Severity depends far more on call frequency than on query shape.

| Class | Meaning |
|---|---|
| **Hot** | Runs on every claim attempt, every poll tick, or per unit of work — by every worker and advancer thread simultaneously. Missing index here degrades non-linearly with table size. |
| **Warm** | Runs per pipeline advancement, per job completion, or per reap sweep. |
| **Cold** | Dashboard, CLI, health check, migrations, one-off maintenance. |

The claim paths are the hottest queries in the system and the ones where a
missing or unusable index matters most. Start there.

Cold queries earn a finding only when the table grows unboundedly and the
query is a full scan. Do not file an index for a dashboard query that filters
an already-indexed column.

## Step 3 — Checklist

### 3.1 Missing coverage

- Every `WHERE` column combination on a hot or warm query — is there an index
  whose **leading columns** match? An index on `(a, b)` does not serve a
  query filtering only on `b`.
- Foreign keys and `belongs_to` columns used in lookups.
- Columns backing uniqueness guarantees — is the constraint enforced by a
  **unique index** in the database, or only by an ActiveRecord validation?
  Validation-only uniqueness is a correctness finding, not just performance,
  because concurrent claimers bypass it.
- Columns used in `ORDER BY ... LIMIT 1` — the claim pattern. Without an
  index providing the order, the database sorts the entire candidate set to
  return one row.
- Polymorphic association pairs (`*_type`, `*_id`) indexed together.

### 3.2 Column order and usability

An index can exist and still not be usable for a query:

- **Equality columns first, then range/sort columns.** An index on
  `(status, created_at)` serves `WHERE status = ? ORDER BY created_at`;
  `(created_at, status)` does not.
- Does the `ORDER BY` direction match, and are mixed `ASC`/`DESC` orders
  supported by the index as declared?
- Is a leading column wrapped in a function or cast in the query? That makes
  the index unusable — including implicit casts from a type mismatch between
  the bind and the column.
- Are near-duplicate indexes (`(a, b, c)` and `(a, c, b)`) both actually
  needed by distinct queries, or is one dead weight?

### 3.3 The `IS NULL` ordering trap (PostgreSQL)

**A known and previously diagnosed issue in this codebase — check for new
instances.** A composite index `(a, b, c)` queried as
`WHERE a = ? AND b IS NULL ORDER BY c` will **not** be used for ordering on
PostgreSQL. PostgreSQL does not treat `IS NULL` as an equality constraint for
index-ordering purposes, so you get a bitmap scan plus a sort instead of an
ordered index scan — which defeats the `LIMIT 1` entirely.

The fix is a partial index moving the null test into the predicate:
`ON table (a, c) WHERE b IS NULL`.

This is exactly the shape the claim paths use (`claimed_for_advancing_at IS
NULL`, `completed_at IS NULL`), so check every one of them.

### 3.4 Partial indexes and adapter portability

Partial indexes (`where:`) work on PostgreSQL and SQLite. **MySQL does not
support them at all.**

The codebase already handles this with `if mysql?` / `else` branches that
substitute a full index. For every partial index:

- Is there a MySQL fallback branch, or does that adapter silently get no
  index?
- Is the fallback actually useful for the query, or is it a full index whose
  leading column has terrible selectivity?
- If a fix requires a partial index, state explicitly what MySQL gets
  instead. A recommendation that only works on Postgres is incomplete.

Also confirm the predicate is expressible: Cockroach and SQLite accept
partial indexes but have their own restrictions on the predicate expression.

### 3.5 Redundant and over-indexed

Indexes are not free — every one is written on every insert and update, and
these tables are write-heavy by nature.

- Is any index a **strict prefix** of another? `(a)` is redundant when
  `(a, b)` exists and nothing needs `(a)` alone for uniqueness.
- Are there indexes no query in the inventory uses? Cross-reference inventory
  1a against 1b and list the unmatched ones.
- Does a table have so many indexes that insert cost is a concern? Call out
  the write amplification on the hot insert paths.

Report these as Low or Medium — real, but the risk of removal is nonzero and
the reader should decide.

### 3.6 Adapter-specific limits

- **MySQL index key length.** Indexed string columns count toward a byte
  limit (3072 bytes with InnoDB/DYNAMIC, and 767 in older configurations).
  Non-Postgres installs store UUIDs as `string(36)` rather than a native
  `uuid` type, so composite indexes over several ID columns are far wider
  there than on Postgres. Check the widest composite indexes.
- **Identifier length.** Oracle historically caps identifiers at 30
  characters (128 in 12.2+). Auto-generated index names over long
  `ductwork_*` table and column names can exceed it. Check the longest
  generated names and recommend an explicit `name:` where they are at risk.
- Does `MigrationHelper` gate the index correctly for every supported
  adapter, or does an adapter fall through to a branch meant for another?

## Step 4 — Verify and report

Follow `method.md`. Additionally, every index finding must state:

1. **The exact query** — file:line — that is unserved.
2. **The access pattern** — `WHERE` columns, `ORDER BY`, `LIMIT`.
3. **What the database does today** without the index (full scan, sort of the
   candidate set, bitmap plus sort) and how that scales.
4. **The proposed index**, in migration form, with column order justified.
5. **The MySQL story** if the proposal is partial.
6. **Both landing sites** — install template and a new upgrade migration.

Do not claim a query plan you have not verified. If you are inferring the
plan from the index shape rather than from an `EXPLAIN`, say so and mark the
finding medium confidence. `EXPLAIN` requires a live database and is out of
scope for this audit unless the user supplies one.
