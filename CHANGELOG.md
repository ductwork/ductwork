# Ductwork Changelog

## [0.19.0] (Unreleased)

- feat: add "role" configuration - to be used to set the role of the entire ductwork running instance

## [0.18.0]

- fix: show countdown for pipelines/steps scheduled in the future
- feat: add input and output arguments to pipeline dashboard page
- feat: add RSpec matcher for asserting pipeline context

## [0.17.0]

- feat: assign step node names unique hex values in the pipeline definition
- chore: remove unnecessary logging

## [0.16.0]

- feat!: allow `Pipeline.trigger` to accept arbitrary positional arguments - this is a BREAKING CHANGE as it changes the structure of how arguments are stored and passed between steps
- feat: add RSpec testing helper for setting context state
- feat: add RSpec testing helper for easily creating pipelines

## [0.15.1]

- fix: pass pipeline ID directly to step builder method instead of passing step object

## [0.15.0]

- chore: remove unnecessary transaction in job enqueueing method
- feat: expose pipeline and step classes validation method instead of running in a rails initializer
- feat!: introduce pipeline Context - this is a BREAKING CHANGE because step classes now need to inherit from `Ductwork::Step`; they are no longer POROs

## [0.14.1]

- fix: check if steps and pipelines directories exist before eager loading

## [0.14.0]

- feat: add support for ruby v4.0

## [0.13.1]

- fix: order step executions by started at

## [0.13.0]

- feat: print CLI banner on boot
- feat: add and populate `ductwork_pipelines.halted_at` timestamp
- fix: fix style violations
- fix: remove `config/ductwork.yml` test file after each test run
- feat: mount rails engine in routes file with install generator
- feat: implement a basic web dashboard
- feat: isolate `Ductwork` namespace - this is in prep for a web dashboard

## [0.12.0]

- chore: replace usages of `Pipeline#halted!` with `Pipeline#halt!`
- feat: create `Ductwork::Pipeline#halt!` method
- chore: extract `Ductwork::Pipeline#complete!` method

## [0.11.2]

- fix: join error backtrace lines before persisting in `text` column
- fix: use computed `max_retry` when determining job retry
- fix: protect against a possible null `status` when advancing a pipeline
- fix: correct spelling of `last_heartbeat_at` variable
- fix: flip inverted deadline check in job worker runner
- fix: flip inverted deadline check in pipeline advancer runner
- fix: reference `thread` variable from `job_worker`, not top-level
- fix: remove unnecessary, erroneous line in definition builder

## [0.11.1]

- fix: use info-level for job worker restart log messages
- fix: use "killed" result in job execution log message when job worker is restarted

## [0.11.0]

- feat: expose `job` attribute during claim and execution in job worker

## [0.10.0]

- chore: update thread health-check logging

## [0.9.2]

- fix: correctly set last node to node id instead of class name

## [0.9.1]

- fix!: assign unique node names (klass name and stage) in pipeline definition DAG - this is a BREAKING CHANGE because the pipeline definition structure has changed

## [0.9.0]

- feat: add health check to job worker runner process - this is a basic check if a thread is healthy via `Thread#alive?` and restarts the thread if it is dead

## [0.8.1]

- fix: properly wrap "units of work" in rails application executor in pipeline advancer
- fix: remove wrapping thread creation with the rails application executor - these threads are long-running so they should not be wrapped; later commits will wrap each individual "unit of work" with the executor as recommended
- fix: move pipeline advancer creation into thread initialization block - this effectively doesn't change anything but is useful in case we need to do something on the advancer thread in the initializer
- fix: move job worker creation into thread initialization block - this effectively doesn't change anything but is useful in case we need to do something on the worker thread in the initializer

## [0.8.0]

- chore: re-organize `Ductwork::CLI` class
- feat!: better name `ductwork_steps.step_type` to `to_transition` - the column rename is a breaking change but not bumping major version since the gem is still pre-1.0
- feat: add `delay_seconds` and `timeout_seconds` columns to `ductwork_steps` table
- feat: set pipeline status to `advancing` once pipeline is claimed and advancing starts
- chore: add `advancing` status enum value to `Pipeline`

## [0.7.2]

- chore: small DRY refactor in pipeline advancement

## [0.7.1]

- chore: isolate on halt execution in `Ductwork::Job#execution_failed!`
- chore: add pipeline definition metadata to `DefinitionBuilder` initializer

## [0.7.0]

- feat: set `Pipeline` and `Step` models status to "in-progress" when claiming latest job

## [0.6.1]

- chore: update misc development dependencies
- fix: eager load pipelines and steps directory after rails initialization - the lazy load hook originally being used would fire before the `rails.main` autoloader had fully setup; when trying to eager load the directories a `Zeitwerk::SetupRequired` error would be raised

## [0.6.0]

- feat: expose `Ductwork.eager_load` method for eager loading code via `zeitwerk`
- chore: let `zeitwerk` autoload models from `lib/models` directory instead of letting rails autoload them from the `app/models` directory via the rails engine
- feat: add `started_at` column to `ductwork_pipelines` table - for now, this will only be used in Pro features.

## [0.5.0]

- chore: add "waiting" status to `Step` model
- chore: add "waiting" status to `Pipeline` model
- fix: change `jobs.input_args` and `jobs.output_payload` column type to `text`
- fix: change `pipelines.definition` column type to `text` - this prevents larger definitions from being clipped if there is a size limit on the string column
- feat: add missing unique index on `ductwork_results` and `ductwork_runs` tables
- feat: add missing composite index on `ductwork_executions` table for `Ductwork::Job.claim_latest` method
- feat: add missing composite index on `ductwork_availabilities` table for `Ductwork::Job.claim_latest` method
- feat: use array instead of ActiveRecord relation when advancing pipelines - this has major performance benefits but comes with memory-usage implications (see comments)
- fix: add condition to query to return correct pipelines that need advancing
- fix: release pipeline claim only if successfully claimed
- chore: add pipeline ID to misc log lines
- feat: add missing composite indexes on `ductwork_steps` table

## [0.4.0]

- chore: change job worker thread name format
- feat: add and respect pipeline-level `pipeline_advancer.polling_timeout` configuration in pipeline advancer
- feat: respect `job_worker.polling_timeout` configuration in job runner
- feat: add pipeline-level `job_worker.polling_timeout` configuration
- feat: check pipeline and step-level max retry configurations when retrying a job
- feat: add pipeline and step-level `job_worker.max_retry` configurations
- feat: add ability to set `job_worker.count` config manually
- chore: move configuration specs under their own directory
- feat: halt pipeline instead of erroring if max step depth is exceeded
- chore: move specs under directory
- feat: allow setting `pipeline_advancer.steps_max_depth` configuration manually
- feat: raise `Ductwork::Pipeline::StepDepthError` error if return payload count exceeds the configuration
- feat: add `pipeline_advancer.steps.max_depth` configuration

## [0.3.1]

- chore: bump dependencies and update necessary files
- chore: update email address in gemspec
- chore: move `logger` out of config to top-level `Ductwork` module
- chore: promote `Ductwork::Pipeline#parsed_definition` to a public method
- fix: raise when trying to collapse a most recently divided pipeline and vice versa

## [0.3.0]

- fix: correctly create collapsing and combining steps and jobs for complex pipelines
- fix: add a new step and job for each active branch in a running pipeline
- fix: add a new node and edge for each active branch of the definition
- feat: add info-level logging for job events
- feat: add info-level logging for pipeline events

## [0.2.1]

- fix: do not splat arguments when executing a job nor triggering a pipeline
- fix: do not splat arguments when enqueuing a job and fix related spec
- fix: add missing `dependent: :destroy` on certain associations

## [0.2.0]

- feat: validate all pipeline definitions on rails boot
- feat: validate argument(s) passed to step transition DSL methods to be valid step class
- fix: allow steps to be chained while pipeline is expanded or divided (before collapsing or combining) - before this incorrectly raised a `CollapseError` or `CombineError`

## [0.1.0]

- Initial release - see [documentation](https://docs.getductwork.io/) for details
