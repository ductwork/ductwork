# Ductwork

A ruby pipeline framework.

Ductwork allows you to build pipelines quickly and easily using tooling and a DSL that feels naturally Ruby. No need to learn some unified object model or stand up separate runner instances.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add ductwork
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install ductwork
```

Once installed, you can use the rails generator to create the binstub, config file with defaults, and migrations. Execute it with:

```bash
bin/rails generate ductwork:install
```

Run migrations and you're ready to pipeline!

### Multi-Database

If you're running multiple database in your rails application, you may decide to dedicate a database to `ductwork`. In that case, move the migrations under the migrations path configured for that database and be sure to use the `database` configuration. See the Configuration section for more details.

## Configuration


Ductwork is configured through a configuration file. The default lives at `config/ductwork.yml` As you'll learn more further down, there is a CLI option for specifying the configuration file's path. This allows you to have multiple instances of `ductwork` run different pipelines. Below are a few important configurations; for a complete list of configuration values, descriptions, and defaults see the online documentation.

### Pipelines

This configuration value sets the pipelines to run. Running a pipeline means running a "pipeline advancer" process and a "job worker" process that creates threads. For more information on the concurrency model of `ductwork` see the online documentation.

```yaml
default: &default
  piplines:
    - MyPipelineA
    - MyPipelineB
```

Use the wildcard `"*"` to run all defined pipelines:

```yaml
default: &default
  piplines: "*"
```

**NOTE**: Use with caution as this can eat up a lot of resources if you have many defined pipelines!

### Job Worker Count

This configuration value sets the number of threads that are created for each running pipeline's job worker process. These threads are responsible for running the actual job for each step. The default is 5.

```yaml
default: &default
  job_worker:
    worker_count: 10
```

**NOTE**: Be sure to properly scale the rails connection pool size so the number of threads and connections are equal.

### Job Worker Max Retry

This configuration value sets the number of times a step's job can be retried before marking it as an error and halting the pipeline. The default is 3.

```yaml
default: &default
  job_worker:
    max_retry: 3
```

## Usage

The main usage pattern for `ductwork` is to

1. Create a pipeline class
1. Use the DSL to define the pipeline steps
1. Create the step classes
1. Run the `bin/ductwork` process using the CLI
1. Trigger pipelines to run

### Create a Pipeline

All pipeline classes must live under `app/pipelines`. A pipeline's class name does not necessarily need to have a suffix of "Pipeline", however, it may be good practice to avoid naming collisions. To properly create a pipeline you must inherit from the `Ductwork::Pipeline` class:

```ruby
# app/pipelines/enrich_user_data_pipeline.rb
class EnrichUserDataPipeline < Ductwork::Pipeline
end

# app/pipelines/enrich_user_data.rb
class EnrichUserData < Ductwork::Pipeline
end
```

### Define Steps and Transitions

`ductwork` provides a DSL (Domain Specific Language) for defining pipeline Steps and the Transitions between them. Steps are simply classes that live under `app/steps` and have an `#execute` instance method. The arity of the initializer depends on the arguments passed when triggered or the previous Step's return value. Because of the simple interface, Steps are easily testable as POROs (Plain Old Ruby Objects) without needing external dependencies (unless your logic requires it). Similar to pipelines, step class names do not need a "Step" suffix, but again, it may provide naming benefits. Assuming one of the pipelines above exists, continue with an example:

```ruby
# app/steps/users_requiring_enrichment.rb`
class UsersRequiringEnrichment
  def initialize(days_outdated)
    @days_outdated = days_outdated
  end

  def execute
    ids = User.where("data_last_refreshed_at < ?", days_outdated.days.ago).ids

    Rails.logger.info("Enriching #{ids.length} users' data")

    # We specifically return the collection of IDs because we want this
    # as the argument to the next step.
    ids
  end
end
```

Conceptually, Steps represent a checkpoint in your pipeline. They are intended to run in a short amount of time. The philosophy is to break down long running jobs into smaller work units by pipelining steps and passing return data.

Now that we've covered Steps, let's go over Transitions. The most important thing to remember with transitions is that the return value of the previous step is the input to the next step. This requires you to align arity of the initializer between each step. It's not as hard as it may sounds when you have good tests in place. The other option is to use the splat operator for all arguments and treat everything as a collection. One other condiferation is that argument types must be JSON serializable.

Below each Transition DSL method is used:

#### `start`

```ruby
class EnrichUserDataPipeline < Ductwork::Pipeline
  define do |pipeline|
    pipeline.start(UsersNeedingEnrichment)
            .expand(to: LoadUserData)
            .divide(to: [FetchDataFromSourceA, FetchDataFromSourceB])
            .combine(into: CollateUserData)
            .chain(UpdateUserData)
            .collapse(into: ReportUserEnrichmentSuccess)
  end
end
```

The DSL also affords specifying a class to call when any step exceeds the maximum number of retries and the pipeline halts. Do this by passing a class to the `on_halt` DSL method. The class can live anywhere but makes the most sense under `app/steps` since it has a similar interface. The class must adhere to a defined interface:

* `#initialize/1` - The initializer is required to take a single argument. The argument will be the last error instance of the last step that ran.
* `#execute/0` - Similar to Steps, the on-halt class only needs a single `#execute` instance method.

A code example is below for how to configure it in your pipeline:

```ruby
class EnrichUserData < Ductwork::Pipeline
  define do |pipeline|
    pipeline.on_halt(PageOnCallEngineer)
  end
end
```

### Running the Ductwork Process

After running the rails generator you will have a new binstub at `bin/ductwork`. This executable starts the supervisor which then forks a pipeline advancer and step workers for each configured pipeline.

The CLI has a single option specified by either `-c` or `--config`. It takes a path to the YAML configuration file you want to load for the running instance of `ductwork`.

### Triggering a Pipeline

All that's left now is to call the pipeline in your code! Triggering a pipeline returns a `Ductwork::Pipeline` instance.

```ruby
rake :enrich_user_data do
  EnrichUserDataPipeline.trigger(7)
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ductwork/ductwork. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/ductwork/ductwork/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Ductwork project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/ductwork/ductwork/blob/main/CODE_OF_CONDUCT.md).
