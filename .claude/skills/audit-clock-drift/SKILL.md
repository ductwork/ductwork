---
name: audit-clock-drift
description: Audit ductwork for time comparisons that are prone to clock drift
allowed-tools: Read, Grep, Glob
---

# Audit Clock Drift

Audit the entire OSS ductwork codebase for places where we are open to clock drift issues. Specifically, if ductwork is running across multiple hosts, where are we prone to comparing a database timestamp with an in-memory OS clock read generated with Ruby. Only look for comparisons that gate safety or visibility. For example: heartbeat, enqueueing, claiming, possibly ordering.

For each finding: file:line, severity, why it matters, suggested fix. Do not modify files.
