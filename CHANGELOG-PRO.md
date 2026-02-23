# Ductwork Pro Changelog

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
