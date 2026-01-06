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

RSpec::Matchers.define(:have_set_context) do |expected|
  supports_block_expectations

  match do |block|
    ctx = Ductwork::Context.new(pipeline_id)
    before_values = expected.map { |k, _| ctx.get(k.to_s) }

    block.call

    after_context = expected.to_h { |k, _| [k, ctx.get(k.to_s)] }

    before_values.all?(&:nil?) && after_context == expected
  end

  chain :for_pipeline, :pipeline_id

  failure_message do
    "Context does not match expected result"
  end
end

module Ductwork
  module Testing
    module RSpec
      def pipeline_for(klass, **attrs)
        definition = klass.pipeline_definition.to_json
        definition_sha1 = OpenSSL::Digest::SHA256.hexdigest(definition)
        status = attrs[:status] || "in_progress"
        triggered_at = attrs[:triggered_at] || Time.current
        started_at = attrs[:started_at] || Time.current
        last_advanced_at = attrs[:last_advanced_at] || Time.current

        Ductwork::Pipeline.create!(
          klass:,
          definition:,
          definition_sha1:,
          status:,
          triggered_at:,
          started_at:,
          last_advanced_at:
        )
      end

      def set_pipeline_context(pipeline, **key_values)
        ctx = Ductwork::Context.new(pipeline.id)
        key_values.each do |key, value|
          ctx.set(key.to_s, value)
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.include Ductwork::Testing::RSpec
end
