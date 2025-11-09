# frozen_string_literal: true

RSpec::Matchers.define(:have_triggered_pipeline) do |expected|
  include Ductwork::Testing::Helpers

  supports_block_expectations

  match do |block|
    pipelines = pipelines_created_around(&block)
    delta = pipelines.count
    expected_count = count || 1

    if delta == expected_count
      pipelines.pluck(:klass).uniq.sort == Array(expected).map(&:name).sort
    else
      @failure_result = if delta.zero?
                          :none
                        elsif delta > 1
                          :too_many
                        else
                          :other
                        end

      false
    end
  end

  chain :exactly, :count

  chain :times do # rubocop:disable Lint/EmptyBlock
  end

  failure_message do |actual|
    case @failure_result
    when :none
      "expected to trigger pipeline #{expected} but triggered none"
    when :too_many
      "expected to trigger pipeline #{expected} but triggered more than one"
    when :other
      "expected to trigger pipeline #{expected} but triggered #{actual}"
    else
      "expected to trigger pipeline #{expected} but did not"
    end
  end
end

RSpec::Matchers.define(:have_triggered_pipelines) do |*expected|
  include Ductwork::Testing::Helpers

  supports_block_expectations

  match do |block|
    pipelines = pipelines_created_around(&block)

    pipelines.map(&:klass).sort == expected.map(&:name).sort
  end

  failure_message do |_actual|
    pipeline_names = expected.map(&:name).join(", ")

    "expected to trigger pipelines: #{pipeline_names} but did not"
  end
end
