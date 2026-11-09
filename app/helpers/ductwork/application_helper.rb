# frozen_string_literal: true

module Ductwork
  module ApplicationHelper
    NO_VALUE = "—"
    SHORT_ID_LENGTH = 8

    def formatted_time_distance(started_at, completed_at)
      elapsed = completed_at - started_at

      return "#{elapsed.round(2)}s" if elapsed < 60

      hours = (elapsed / 3600).floor
      minutes = ((elapsed % 3600) / 60).floor
      seconds = (elapsed % 60).floor
      parts = { "h" => hours, "m" => minutes, "s" => seconds }.reject { |_, value| value.zero? }

      parts.map { |unit, value| "#{value}#{unit}" }.join(" ")
    end

    def runtime(record)
      finished_at = record.completed_at || record.try(:halted_at)

      if finished_at.present?
        formatted_time_distance(record.started_at, finished_at)
      elsif record.started_at.nil? || record.try(:failed?)
        no_value
      else
        tag.span(
          formatted_time_distance(record.started_at, Time.current),
          data: { started_at: record.started_at.iso8601(3) }
        )
      end
    end

    def timestamp(time)
      return no_value if time.nil?

      iso8601 = time.iso8601(3)

      tag.time(time.strftime("%b %-d, %H:%M:%S"), datetime: iso8601, title: iso8601)
    end

    # NOTE: Primary keys are UUID v7, so the leading characters are a timestamp
    # and match across records created together. The tail is the random part.
    def short_id(id)
      tag.code(id.to_s.last(SHORT_ID_LENGTH), title: id)
    end

    def status_badge(status)
      tag.span(status_text(status), class: "status", data: { status: })
    end

    def status_text(status)
      status.tr("_", "-")
    end

    def transition_text(transition)
      transition == "default" ? "chain" : transition
    end

    def count_badge(count, tone: "alert")
      count.zero? ? tag.span(0, class: "faint") : tag.span(number_with_delimiter(count), class: "count-#{tone}")
    end

    def halt_summary(reasons)
      reasons
        .map do |reason, count|
          text = reason&.humanize&.downcase || "unknown reason"

          "#{pluralize(count, "branch")}: #{text}"
        end
        .join(", ")
    end

    def pretty_json(value)
      value.nil? ? "no value" : JSON.pretty_generate(value)
    end

    def step_input(job)
      JSON.parse(job.input_args)["args"] if job&.input_args.present?
    end

    def step_output(job)
      job.return_value if job&.output_payload.present?
    end

    def filtered_path(anchor: nil, **changes)
      url_for(**link_params.except(:page).merge(changes).compact, anchor:)
    end

    def first_page?
      current_page.zero?
    end

    def last_page?(total)
      (current_page + 1) * per_page >= total
    end

    def page_summary(total)
      first = (current_page * per_page) + 1
      last = [first + per_page - 1, total].min

      first > total ? "Showing 0 of #{total}" : "Showing #{first}-#{last} of #{total}"
    end

    def next_page_path(anchor: nil)
      url_for(**link_params, page: current_page + 1, anchor: anchor)
    end

    def previous_page_path(anchor: nil)
      url_for(**link_params, page: [current_page - 1, 0].max, anchor: anchor)
    end

    private

    def link_params
      params
        .permit(:controller, :action, :id, :klass, :node, :status, :page)
        .to_h
        .symbolize_keys
    end

    def no_value
      tag.span(NO_VALUE, class: "faint")
    end
  end
end
