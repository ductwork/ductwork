# Shared Audit Method

Every `audit-*` skill in this repo follows this procedure. The topic-specific
SKILL.md supplies the *what*; this file supplies the *how*.

## Step 1 — Build the inventory before analyzing

Do not start grepping for problems. First enumerate the surface in scope and
write the list down. The audit is only as complete as this list.

- Use Glob/Grep to enumerate every file in the topic's surface.
- Record the count. State it in the report.
- Work the list. A file that was never opened is not a file that passed.

"Audit the entire codebase" without an inventory produces a handful of
findings from whatever grep happened to surface first. That is the single
biggest cause of a thin audit.

## Step 2 — Analyze against the topic checklist

Follow the topic skill's categories in order. For each item on the inventory,
ask the checklist questions explicitly rather than scanning for anything that
looks wrong.

Prefer reading whole files over grepping for patterns. Durability,
concurrency, and adapter bugs live in the *relationship* between lines — the
order of two writes, the extent of a transaction, what a rescue does and does
not cover. Grep finds none of that.

## Step 3 — Verification pass (required)

Before writing the report, re-read every cited `file:line` and confirm the
code still says what the finding claims.

Drop any finding where:
- The line number no longer matches the quoted code.
- The concern is already handled somewhere the first pass missed (a guard in
  the caller, a CAS predicate, an outer `ensure`, a DB constraint).
- It appears in `accepted-tradeoffs.md`.
- It is out of scope per `scope-boundaries.md` (notably: Pro features).

State how many candidate findings were dropped in verification. A pass that
drops nothing usually means the verification did not actually happen.

## Step 4 — Deduplicate

A single line can legitimately trip several audits — a `Time.current`
comparison inside a claim query is both a clock-drift and a durability
finding. Within one audit, report each root cause **once**, at the deepest
layer that owns it, and list the other affected call sites underneath it.
Do not file the same root cause once per call site.

## Output contract

Report inline in the response. Do not write a report file unless asked, and
do not modify any source file.

Order findings by severity (see `severity.md`), highest first. Group by
category only when there are enough findings that grouping helps.

Each finding uses this shape:

```
### [SEVERITY] Short title
`path/to/file.rb:123`

**What:** The specific code and what it does.
**Why it matters:** The concrete failure — the sequence of events that
produces data loss, a stall, double execution, or a wrong result. Not
"this is risky."
**Fix:** A specific change. Name the existing helper or pattern in this
codebase that it should use, if one exists.
**Confidence:** high | medium — and for medium, what you could not verify.
```

Close with a short summary: files inventoried, files read, findings by
severity, candidates dropped in verification.

## When there are no findings

Say so plainly. State what was inventoried and what checklist categories were
checked and came back clean. A clean audit is a valid and useful result.

Do not pad a report with speculative or stylistic findings to make it look
thorough. A "Low" that is really a preference is noise, and it trains the
reader to skim.
