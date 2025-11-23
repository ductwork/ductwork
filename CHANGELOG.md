# Ductwork Changelog

## [0.3.1] (Unreleased)

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
