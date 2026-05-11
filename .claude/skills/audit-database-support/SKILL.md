---
name: audit-database-support
description: Audit ductwork for what database adapters and technologies are supported
allowed-tools: Read, Grep, Glob
---

# Audit Clock Drift

Audit the entire OSS ductwork codebase for code and queries that do not support a certain database adapters or technology. Ensure support for:

* PostgreSQL
* CockroachDB
* MySQL 8+ (adapter and technology)
* Trilogy (adapter)
* SQLite
* Oracle

For each finding: file:line, severity, why it matters, suggested fix. Do not modify files.
