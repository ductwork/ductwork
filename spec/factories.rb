# frozen_string_literal: true

FactoryBot.define do
  factory :advancement, class: "Ductwork::Advancement" do
    started_at { Time.current }
    process
    transition

    trait :errored do
      error_klass { "StandardError" }
      error_message { "bad times" }
      error_backtrace { "(main)" }
    end
  end

  factory :attempt, class: "Ductwork::Attempt" do
    started_at { Time.current }
    execution
  end

  factory :availability, class: "Ductwork::Availability" do
    started_at { Time.current }
    pipeline_klass { "MyPipeline" }
    execution
  end

  factory :branch, class: "Ductwork::Branch" do
    last_advanced_at { Time.current }
    pipeline_klass { "MyPipeline" }
    started_at { Time.current }
    status { Ductwork::Branch.statuses.keys.sample }
    run

    trait :in_progress do
      status { "in_progress" }
    end

    trait :completed do
      status { "completed" }
      completed_at { Time.current }
    end

    trait :halted do
      status { "halted" }
      halt_reason { "advancer_retries_exhausted" }
    end
  end

  factory :execution, class: "Ductwork::Execution" do
    started_at { Time.current }
    retry_count { 0 }
    job
  end

  factory :job, class: "Ductwork::Job" do
    started_at { Time.current }
    klass { "MyStepA" }
    input_args { { args: [1] }.to_json }
    step
  end

  factory :pipeline, class: "Ductwork::Pipeline" do
    sequence(:klass) { |n| "MyPipeline#{n}" }
    status { Ductwork::Pipeline.statuses.keys.sample }

    trait :completed do
      status { "completed" }
    end

    trait :halted do
      status { "halted" }
    end
  end

  factory :process, class: "Ductwork::Process" do
    sequence(:pid, &:itself)
    sequence(:machine_identifier) { |n| "Machine#{n}" }
    last_heartbeat_at { Time.current }

    trait :current do
      pid { ::Process.pid }
      machine_identifier do
        File.read("/etc/machine-id").strip.presence || Socket.gethostname
      rescue Errno::ENOENT
        Socket.gethostname
      end
    end
  end

  factory :result, class: "Ductwork::Result" do
    result_type { Ductwork::Result.result_types.values.sample }
    execution
  end

  factory :run, class: "Ductwork::Run" do
    sequence(:pipeline_klass) { |n| "MyPipeline#{n}" }
    status { Ductwork::Pipeline.statuses.keys.sample }
    started_at { Time.current }
    triggered_at { Time.current }
    definition { JSON.dump({}) }
    definition_sha1 { Digest::SHA1.hexdigest(definition) }
    pipeline

    trait :halted do
      status { "halted" }
    end
  end

  factory :step, class: "Ductwork::Step" do
    node { "MyFirstStep.0" }
    klass { "MyFirstStep" }
    started_at { Time.current }
    status { Ductwork::Step.statuses.keys.sample }
    to_transition { Ductwork::Step.to_transitions.keys.sample }
    run
    branch

    trait :advancing do
      status { "advancing" }
    end

    trait :failed do
      status { "failed" }
    end

    trait :completed do
      status { "completed" }
      completed_at { Time.current }
    end
  end

  factory :transition, class: "Ductwork::Transition" do
    started_at { Time.current }
    branch
    in_step factory: :step
    out_step factory: :step
  end

  factory :tuple, class: "Ductwork::Tuple" do
    sequence(:key) { |n| "key#{n}" }
    serialized_value { { raw_value: "foobar" }.to_json }
    first_set_at { Time.current }
    last_set_at { Time.current }
    run
  end
end
