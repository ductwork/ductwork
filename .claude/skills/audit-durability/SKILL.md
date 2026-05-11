---
name: audit-durability
description: Audit ductwork for durability gaps
allowed-tools: Read, Grep, Glob
---

# Durability Audit Gap

Audit the entire OSS ductwork codebase for durability gaps.

Check for:
1. **Stuck pipelines**: claims without transition records, advancements without completion, missing reaper coverage
2. **Lost data**: writes after observable side effects, missing "write before you act" ordering, places where partial failure is not handled
3. **Double execution**: missing fencing on claim token or process ID, missing idempotency on transitions, gaps in two-phase commit
4. **Reaper clobberins**: heartbeat updates racing reaper swwps, stale claim token assumptions, missing recoery count increments
