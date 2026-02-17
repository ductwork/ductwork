# Ductwork

[![CI](https://github.com/ductwork/ductwork/actions/workflows/main.yml/badge.svg)](https://github.com/ductwork/ductwork/actions/workflows/main.yml)
[![Gem Version](https://badge.fury.io/rb/ductwork.svg?icon=si%3Arubygems)](https://rubygems.org/gems/ductwork)

A Ruby pipeline framework.

Ductwork lets you build complex pipelines quickly and easily using intuitive Ruby tooling and a natural DSL. No need to learn complicated unified object models or stand up separate runner instances—just write Ruby code and let Ductwork handle the orchestration.

There is also a paid [Ductwork Pro](https://www.getductwork.io/) version with more features and support. See the [Pricing](https://www.getductwork.io/#pricing) page to buy a license.

**[Full Documentation](https://docs.getductwork.io/)**

## Installation

Add Ductwork to your application's Gemfile:

```bash
bundle add ductwork
```

Run the Rails generator to create the binstub, configuration file, and migrations:

```bash
bin/rails generate ductwork:install
```

**NOTE**: run the update generator if you've already installed ductwork to get updates:

```bash
bin/rails generate ductwork:update
```

Run migrations and you're ready to start building pipelines!

## Configuration


The only required configuration is specifying which pipelines to run. Edit the default configuration file `config/ductwork.yml`:

```yaml
default: &default
  pipelines:
    - EnrichUserDataPipeline
    - SendMonthlyStatusReportsPipeline
```

Or use the wildcard to run all pipelines (use cautiously—this can consume significant resources):

```yaml
default: &default
  pipelines: "*"
```

See the [Configuration Guide](https://docs.getductwork.io/getting-started/configuration.html) for all available options including thread counts, timeouts, and database settings.

## Usage

### 1. Create a Pipeline Class

Pipeline classes live in `app/pipelines` and inherit from `Ductwork::Pipeline`. While the "Pipeline" suffix is optional, it can help avoid naming collisions:

```ruby
# app/pipelines/enrich_user_data_pipeline.rb
class EnrichUserDataPipeline < Ductwork::Pipeline
end
```

### 2. Define Steps

Steps are Ruby objects that inherit from `Ductwork::Step` and implement two methods:
- `initialize` - accepts parameters from the trigger call or previous step's return value
- `execute` - performs the work and returns data for the next step

Steps live in `app/steps`:

```ruby
# app/steps/users_requiring_enrichment.rb
class QueryUsersRequiringEnrichment < Ductwork::Step
  def initialize(days_outdated)
    @days_outdated = days_outdated
  end

  def execute
    ids = User.where("data_last_refreshed_at < ?", @days_outdated.days.ago).ids
    Ductwork.logger.info("Enriching #{ids.length} users' data")

    # Return value becomes input to the next step
    ids
  end
end
```

### 3. Define Transitions

Connect steps together using Ductwork's fluent interface DSL. The key principle: **each step's return value becomes the next step's input**.

```ruby
class EnrichUserDataPipeline < Ductwork::Pipeline
  define do |pipeline|
    pipeline.start(QueryUsersRequiringEnrichment)  # Start with a single step
            .expand(to: LoadUserData)              # Fan out to multiple steps
            .divide(to: [FetchDataFromSourceA,     # Split into parallel branches
                         FetchDataFromSourceB])
            .combine(into: CollateUserData)        # Merge branches back together
            .chain(to: UpdateUserData)             # Sequential processing
            .collapse(into: ReportSuccess)         # Gather expanded steps
  end
end
```

**Important:** Return values must be JSON-serializable.

See [Defining Pipelines](https://docs.getductwork.io/getting-started/defining-pipelines.html) for detailed documentation.

### 4. Run Ductwork

Start the Ductwork supervisor, which manages pipeline advancers and job workers for each configured pipeline:

```bash
bin/ductwork
```

Use a custom configuration file if needed:

```bash
bin/ductwork -c config/ductwork.0.yml
```

### 5. Trigger Your Pipeline

Trigger pipelines from anywhere in your Rails application. The `trigger` method returns a `Ductwork::Pipeline` instance for monitoring:

```ruby
# In a Rake task
task enrich_user_data: :environment do
  pipeline = EnrichUserDataPipeline.trigger(7)
  puts "Pipeline #{pipeline.id} started"
end

# In a controller
def create
  pipeline = EnrichUserDataPipeline.trigger(params[:days_outdated])

  render json: { pipeline_id: pipeline.id, status: pipeline.status }
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ductwork/ductwork. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/ductwork/ductwork/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [LGPLv3.0 License](https://github.com/ductwork/ductwork/blob/main/LICENSE.txt).

## Code of Conduct

Everyone interacting in the Ductwork project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/ductwork/ductwork/blob/main/CODE_OF_CONDUCT.md).
