# Ductwork Changelog

## [0.5.0] (Unreleased)

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
