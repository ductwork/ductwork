# frozen_string_literal: true

RSpec.describe "PipelinesController#index", type: :request do
  describe "GET /ductwork/pipelines" do
    def page
      Nokogiri::HTML(response.body)
    end

    def error_for(run)
      step = create(:step, run:)
      execution = create(:execution, job: create(:job, step:))
      create(:result, execution: execution, result_type: "failure")
    end

    it "renders successfully" do
      create(:result)

      get "/ductwork/pipelines"

      expect(response).to have_http_status(:ok)
    end

    it "counts each run's errors separately" do
      pipeline = create(:pipeline)
      earlier = create(:run, pipeline: pipeline, pipeline_klass: "Billing", started_at: 1.hour.ago)
      latest = create(:run, pipeline: pipeline, pipeline_klass: "Billing", started_at: Time.current)
      2.times { error_for(earlier) }
      error_for(latest)

      get "/ductwork/pipelines", params: { klass: "Billing" }

      expect(page.css("td.numeric").map { |cell| cell.text.strip }).to eq(%w[1 2])
    end

    it "keeps the class filter on the status tabs" do
      create(:run, pipeline_klass: "Billing", status: "halted")

      get "/ductwork/pipelines", params: { klass: "Billing" }

      expect(page.css(".tab").map { |tab| tab["href"] })
        .to eq(["/ductwork/pipelines?klass=Billing", "/ductwork/pipelines?klass=Billing&status=halted"])
    end

    it "disables next when there are no more runs" do
      create(:run)

      get "/ductwork/pipelines"

      expect(page.css(".pager-link").last["aria-disabled"]).to eq("true")
    end

    it "does not run a halted pipeline's timer" do
      started_at = 90.seconds.ago
      create(:run, status: "halted", started_at: started_at, halted_at: started_at + 30.seconds)

      get "/ductwork/pipelines"

      expect(page.at_css("[data-started-at]")).to be_nil
      expect(response.body).to include("30.0s")
    end

    it "ticks the timer of a running pipeline" do
      create(:run, status: "in_progress")

      get "/ductwork/pipelines"

      expect(page.at_css("[data-started-at]")).not_to be_nil
    end
  end
end
