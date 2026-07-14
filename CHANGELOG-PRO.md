# Ductwork Pro Changelog

## [1.0.0] (Unreleased)

- chore: wire payloads to jobs without instantiating whole model objects
- fix: avoid race condition of `nil`-ing out `execution` on job worker
- fix: no longer strand `combine`/`collapse` branches in `advancing` when a run-row deadlock rolls back a transition that had already completed the branch (via the shared OSS claim-fence fix); previously the run stalled until the advancer process was reaped
- fix: lock the run `FOR NO KEY UPDATE` on Postgres in `resolve_terminal_state!` to avoid the run-row deadlock between concurrent `combine`/`collapse` transitions
- fix: resolve the `collapse` fan-in barrier via `barrier_node` so intermediate `divide`/`combine`/`chain` transitions and nested expands no longer create duplicate collapse targets
- feat: record the matching `expand` node as `barrier_node` on `collapse` edges in the pipeline definition
- fix: lower payload enveloped value limit to ~1GB
- fix: print banner on boot
- fix: avoid per-batch sort when wiring large collapse fan-ins
- fix: remove unnecessary ordering so existing index is hit
- fix: add index to support a keyset `ORDER BY` query for payloads
- feat: stream large collapse fan-ins via lazy input payloads
- feat: stream large expand fan-outs via lazy output payloads
- fix: make changes to reach parity with OSS
- fix: use existing count attribute on branch instead of `COUNT` query
- fix: create composite index for the collapse fan-in read
- chore: do not instantiate full payload activerecord models
- fix: insert payload records in batches of 1_000
- fix: harden the kill-and-restart path against thread hangs
- chore: move configurable pipeline advancer thread pool to the OSS gem
- fix: replace unnecessary lock with atomic, conditional increment
- chore: add advancement integration durability tests
- feat: make `collapse` interruptible, resumeable, and recoverable
- feat: track `collapse` fan-in with counters on `ductwork_branches`
- perf: collapse fan-in via atomic counter instead of scanning siblings
- feat: read `ductwork_payloads` records when executing jobs
- feat: set `ductwork_payloads.to_job_id` when advancing a branch via `collapse`
- feat: set `ductwork_payloads.to_job_id` when advancing a branch via `expand`
- fix: associate `ductwork_payloads` with `ductwork_executions` for origination
- feat: set `ductwork_payloads.to_job_id` when resuming a `dampen`-ed pipeline run
- feat: set `ductwork_payloads.to_job_id` when advancing a branch via `converge`
- feat: set `ductwork_payloads.to_job_id` when advancing a branch via `divide`
- feat: set `ductwork_payloads.to_job_id` when advancing a branch via `divert`
- feat: set `ductwork_payloads.to_job_id` when advancing a branch via `combine`
- feat: set `ductwork_payloads.to_job_id` when advancing a branch via `chain`
- fix: add `position` column to `ductwork_payloads` table
- feat: store step output payloads in `ductwork_payloads` records
- feat: support all OSS v1.0 changes
- fix: release branch in `Ductwork::Pro::Run#resume!`
- fix: set status for pipeline, run, and branch when resuming
- feat: add back dampening during advancement
- feat: respect delay in definition when advancing branches
- fix: properly release branch when execution times out
- fix: call methods on `branch` in pipeline advancer
- fix: use correct associations in `JobWorker#timed_out?`
- fix: do not advance pipeline on job timeouts
- feat: move dampening and resuming to `Run` with a top-level `Pipeline#resume!`
- fix: properly report metrics when pipeline run completes or halts
- fix: create `runs` and `branches` records when triggering pipeline
- chore: change `dampers` association to `runs` instead of `pipelines`
- chore: regenerate spec migrations to pick up `ductwork` v1.0.0 changes

## [0.8.0]

- feat: support delay and timeout arguments for `divert` and `converge` transitions - this is the last of adding support for the new transitions
- fix: wrap code with rails app executor
- feat: support `divert` and `converge` transitions in pipeline advancement

## [0.7.0]

- feat: allow for passing an argument when resuming a pipeline - this will replace passing the previous step's output payload as the input arguments to the next step

## [0.6.0]

- feat: introduce `dampen` transition - this is the first iteration of the human-in-the-loop feature
- fix: bump `ductwork` dependency to v0.25.0
- fix: bump `ductwork` dependency to v0.24.0
- fix: bump `ductwork` dependency to v0.23.0 and set pipeline klass when creating availabilities
- feat: add optional `to` keyword argument to `chain` transition - this makes the DSL a bit more aligned

## [0.5.0]

- feat: enqueue jobs in batches when expanding and support starting delays

## [0.4.0]

- feat: release pipeline or job claim if not finished by shutdown timeout - this is basically the same as what happens when a step times out except we don't restart the thread because we're shutting down
- fix: move logging to correct location
- fix: correctly wrap all queries in transaction

## [0.3.0]

- feat: extract thread health check logic into class and use in pipeline advancer runner, job worker runner, and thread supervisor
- feat: correctly detect and restart timed out jobs and stuck threads when checking job worker health
- feat: override `PipelineAdvancerRunner#start_pipeline_advancers` to create multiple pipeline advancers based on configuration
- feat: create `ThreadSupervisor` and use in `ThreadSupervisorRunner` - in coming commits we will override `ThreadSupervisor#check_thread_health` to include Pro-specific features
- feat: override methods to launch thread or process supervisor runners
- feat: create `ThreadSupervisorRunner` - this is like `Processes::ThreadSupervisorRunner` except that it creates a pool of pipeline advancers based on configuration
- feat: rename `SupervisorRunner` to `ProcessSupervisorRunner` and override "runner" methods - this is the first in a series of commits that will align Pro with the new process organization in the open-source gem

## [0.2.0]

- chore: remove ruby v3.2.9 from CI testing matrix - support is ending in March '26 but it's being removed now to better support edge rails
- feat: loosen rails version constraint to allow rails edge
- feat: respect "role" configuration by using new process launcher class to insert pro-specific process runners

## [0.1.0]

- Initial release
