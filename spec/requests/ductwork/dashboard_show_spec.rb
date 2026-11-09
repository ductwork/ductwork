# frozen_string_literal: true

RSpec.describe "DashboardsController#show", type: :request do
  describe "GET /ductwork" do
    def page
      Nokogiri::HTML(response.body)
    end

    it "render successfully" do
      create(:result)

      get "/ductwork"

      expect(response).to have_http_status(:ok)
    end

    it "explains an empty install" do
      get "/ductwork"

      expect(response.body).to include("No pipelines have been triggered yet.")
    end

    it "lists a halted pipeline with its reason" do
      run = create(:run, :halted, pipeline: create(:pipeline, status: "halted"), halted_at: Time.current)
      create(:branch, :halted, run: run, halt_reason: "job_retries_exhausted")

      get "/ductwork"

      expect(page.at_css(".halt a")["href"]).to eq("/ductwork/pipelines/#{run.pipeline_id}")
      expect(page.at_css(".halt-reason").text).to eq("1 branch: job retries exhausted")
    end

    it "does not list a halted run whose pipeline has been revived" do
      create(:run, :halted, pipeline: create(:pipeline, status: "in_progress"))

      get "/ductwork"

      expect(page.at_css(".halt")).to be_nil
    end

    it "summarizes pipelines by class" do
      create(:pipeline, klass: "Billing", status: "in_progress")
      create(:pipeline, klass: "Billing", status: "waiting")
      create(:pipeline, klass: "Billing", status: "halted")
      create(:pipeline, klass: "Billing", status: "completed")

      get "/ductwork"

      expect(page.css(".table").first.css("tbody td").map { |cell| cell.text.strip }.first(4))
        .to eq(%w[Billing 2 1 1])
    end
  end
end
