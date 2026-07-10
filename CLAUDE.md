# Ductwork OSS Architecture Context

This is the OSS `ductwork` gem (LGPL v3). The paid `ductwork-pro` gem
extends it via `prepend` and adds features that MUST NOT be reimplemented
or referenced here.

## Lives in OSS (this repo)
- Core workflow transitions: `chain`, `expand`, `divide`, `divert`, `combine`, `converge`, and `collapse`
- Core pipeline DSL
- Two-phase commit (transition + advancement records) for pipeline advancement
- Supervisor / advancer / worker process hierarchy
- Forking + threaded concurrency modes
- Configurable pipeline advancer thread pool
- Heartbeat-based orphan detection
- SKIP LOCKED claiming with atomic UPDATE...WHERE fallback
- Reaper with global-timeout sweeps
- Automatic restart of worker threads stuck in framework code (no execution claimed)
- `Ductwork::Pipeline#revive!` API
- UUID v7 primary keys across PG/MySQL/SQLite
- Rails engine-mountable web dashboard

## Lives in Pro
- Human-in-the-loop functionality with `dampen` transition
- Step timeout feature defined in pipeline definition DSL
- Step delay feature defined in pipeline definition DSL
- Automatic restart of worker threads stuck inside job execution (claimed execution that won't return; via step timeout)
- Large payload support
- Resumable batched fan-out/fan-in
- Interruptible pipeline advancement
- Metric reporting to StatsD

## Hard rules
- Never reference `Ductwork::Pro::*` constants from OSS code.
- Pro extends OSS via `prepend`; OSS must remain functional standalone.
