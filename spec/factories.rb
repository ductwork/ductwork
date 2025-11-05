# frozen_string_literal: true

# This will guess the User class
FactoryBot.define do
  factory :availability, class: "Ductwork::Availability" do
    started_at { Time.current }
    execution
  end

  factory :execution, class: "Ductwork::Execution" do
    started_at { Time.current }
    job
  end

  factory :job, class: "Ductwork::Job" do
    started_at { Time.current }
    klass { "MyStepA" }
    input_args { 1 }
    step
  end

  factory :pipeline, class: "Ductwork::Pipeline" do
    klass { "MyPipeline1" }
    triggered_at { Time.current }
    definition { JSON.dump({}) }
    definition_sha1 { Digest::SHA1.hexdigest(definition) }
    status { Ductwork::Pipeline.statuses.keys.sample }
  end

  factory :step, class: "Ductwork::Step" do
    klass { "MyFirstStep" }
    started_at { Time.current }
    status { Ductwork::Step.statuses.keys.sample }
    step_type { Ductwork::Step.step_types.keys.sample }
    pipeline
  end
end
