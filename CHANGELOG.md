# Ductwork Changelog

## [0.2.1] Unreleased

- fix: do not splat arguments when enqueuing a job and fix related spec
- fix: add missing `dependent: :destroy` on certain associations

## [0.2.0]

- feat: validate all pipeline definitions on rails boot
- feat: validate argument(s) passed to step transition DSL methods to be valid step class
- fix: allow steps to be chained while pipeline is expanded or divided (before collapsing or combining) - before this incorrectly raised a `CollapseError` or `CombineError`

## [0.1.0]

- Initial release - see [documentation](https://docs.getductwork.io/) for details
