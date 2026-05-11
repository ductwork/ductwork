---
name: audit-database-indexes
description: Audit ductwork for missing database indexes
allowed-tools: Read, Grep, Glob
---

# Audit Missing Database Indexes

Audit the entire OSS ductwork codebase for queries that are missing a database index. All migrations live as templates under `lib/generators/ductwork/install/templates/db/**.rb`. Be sure to check all queries and determine if it is a hot path that needs an index. For example, reading next-to-be-claimed IDs, associations, etc. Ensure that suggestions work across at least PostgreSQL, MySQL, and SQLite.

For each finding: file:line, severity, why it matters, suggested fix. Do not modify files.
