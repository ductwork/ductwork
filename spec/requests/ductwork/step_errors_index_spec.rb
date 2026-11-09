# frozen_string_literal: true

RSpec.describe "StepErrorsController#index", type: :request do
  describe "GET /ductwork/step_errors" do
    let!(:result) do
      create(
        :result,
        result_type: "failure",
        error_klass: "NoMethodError",
        error_message: "undefined method 'fart' called on 'foo'",
        error_backtrace: "(main)\nline two"
      )
    end

    it "renders successfully" do
      get "/ductwork/step_errors"

      expect(response).to have_http_status(:ok)
    end

    it "prints the backtrace once" do
      get "/ductwork/step_errors"

      expect(response.body.scan("line two").length).to eq(1)
    end

    it "links to the pipeline" do
      pipeline_id = result.execution.job.step.run.pipeline_id

      get "/ductwork/step_errors"

      expect(Nokogiri::HTML(response.body).css(".row-body a").first["href"])
        .to eq("/ductwork/pipelines/#{pipeline_id}")
    end

    it "shows an empty state when the filter matches nothing" do
      get "/ductwork/step_errors", params: { klass: "Nope" }

      expect(response.body).to include("No step errors match.")
    end
  end
end
