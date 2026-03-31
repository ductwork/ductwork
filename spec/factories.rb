# frozen_string_literal: true

FactoryBot.define do
  factory :advancement, class: "Ductwork::Advancement" do
    started_at { Time.current }
    process
    transition
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
    pipeline

    trait :in_progress do
      status { "in_progress" }
    end

    trait :completed do
      status { "completed" }
      completed_at { Time.current }
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
    input_args { 1 }
    step
  end

  factory :pipeline, class: "Ductwork::Pipeline" do
    sequence(:klass) { |n| "MyPipeline#{n}" }
    triggered_at { Time.current }
    started_at { Time.current }
    last_advanced_at { Time.current }
    definition { JSON.dump({}) }
    definition_sha1 { Digest::SHA1.hexdigest(definition) }
    status { Ductwork::Pipeline.statuses.keys.sample }
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

  factory :step, class: "Ductwork::Step" do
    node { "MyFirstStep.0" }
    klass { "MyFirstStep" }
    started_at { Time.current }
    status { Ductwork::Step.statuses.keys.sample }
    to_transition { Ductwork::Step.to_transitions.keys.sample }
    pipeline
    branch

    trait :advancing do
      status { "advancing" }
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
end
