# Ductwork Pro Architecture Context

This is the OSS `ductwork` gem (LGPL v3). The paid `ductwork-pro` gem
extends it via `prepend` and adds features that MUST NOT be reimplemented
or referenced here.

## Lives in OSS (this repo)
- Core pipeline DSL: `chain`, `expand`, `divide`, `divert`, `combine`, `converge`, and `collapse`
- Two-phase commit (transition + advancement records)
- Supervisor / advancer / worker process hierarchy
- Forking + threaded concurrency modes
- Heartbeat-based orphan detection
- SKIP LOCKED claiming with atomic UPDATE...WHERE fallback
- Reaper with global-timeout sweeps
- `pipeline.revive!` API
- UUID v7 primary keys across PG/MySQL/SQLite

## Lives in Pro
- Human-in-the-loop functionality with `dampen` transition
- Step timeout feature defined in pipeline definition DSL
- Step delay feature defined in pipeline definition DSL
- Automatic restart of stuck threads via heartbeats
- Configurable pipeline advancer thread pool
- Metric reporting to StatsD

## Hard rules
- Never reference `Ductwork::Pro::*` constants from OSS code.
- Pro extends OSS via `prepend`; OSS must remain functional standalone.
