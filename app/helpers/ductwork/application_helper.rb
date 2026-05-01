# frozen_string_literal: true

module Ductwork
  module ApplicationHelper
    def formatted_time_distance(started_at, completed_at)
      elapsed = completed_at - started_at
      hours = (elapsed / 3600).floor
      minutes = ((elapsed % 3600) / 60).floor
      seconds = (elapsed % 60).round(2)
      hours_string = hours.zero? ? "" : "#{hours}h "
      minutes_string = minutes.zero? ? "" : "#{minutes}m "
      seconds_string = seconds.zero? ? "" : "#{seconds}s"

      "#{hours_string}#{minutes_string}#{seconds_string}"
    end

    def first_page?
      params[:page].to_i.zero?
    end

    def next_page_path
      next_page = params[:page].to_i + 1
      next_params = params
                    .permit(:controller, :action, :id, :klass, :status, :page)
                    .merge(page: next_page)

      url_for(**next_params)
    end

    def previous_page_path
      previous_page = params[:page].to_i - 1
      previous_params = params
                        .permit(:controller, :action, :id, :klass, :status, :page)
                        .merge(page: previous_page)

      url_for(**previous_params)
    end
  end
end
