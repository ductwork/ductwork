# frozen_string_literal: true

RSpec.describe "PipelinesController#show", type: :request do
  describe "GET /ductwork/pipelines/:id" do
    it "renders successfully" do
      result = create(:result)
      create(:availability, execution: result.execution)
      create(:attempt, execution: result.execution)
      pipeline_id = result.execution.job.step.run.pipeline_id

      get "/ductwork/pipelines/#{pipeline_id}"

      expect(response).to have_http_status(:ok)
    end

    it "explains why a run halted" do
      run = create(:run, :halted, halted_at: Time.current)
      create(:branch, :halted, run: run, halt_reason: "max_fanout_exceeded")

      get "/ductwork/pipelines/#{run.pipeline_id}"

      expect(Nokogiri::HTML(response.body).at_css(".notice").text).to eq("Halted on 1 branch: max fanout exceeded")
    end

    it "shows each step's input and failed attempts" do
      step = create(:step, status: "failed")
      job = create(:job, step: step, input_args: { args: [{ user: 7 }] }.to_json)
      execution = create(:execution, job:)
      create(:result, execution: execution, result_type: "failure", error_klass: "BoomError", error_message: "boom")

      get "/ductwork/pipelines/#{step.run.pipeline_id}"

      body = Nokogiri::HTML(response.body).at_css(".row-body").text
      expect(body).to include('"user": 7', "BoomError", "boom")
    end

    context "when drawing the workflow" do
      let(:definition) do
        {
          nodes: %w[Start.a Finish.b],
          edges: {
            "Start.a" => { klass: "Start", to: ["Finish.b"], type: "chain" },
            "Finish.b" => { klass: "Finish" },
          },
        }
      end
      let(:run) { create(:run, definition: definition.to_json) }
      let(:path) { "/ductwork/pipelines/#{run.pipeline_id}" }

      before do
        step = create(:step, run: run, klass: "Start", node: "Start.a", status: "failed")
        create(:job, step:)
      end

      def graph
        Nokogiri::HTML(response.body).at_css("svg.graph")
      end

      it "replaces the raw definition with the graph" do
        get path

        expect(graph.css(".graph-node").length).to eq(2)
        expect(graph.css(".graph-edge").length).to eq(1)
        expect(response.body).not_to include("&quot;nodes&quot;")
      end

      it "links a node to its steps" do
        get path

        expect(graph.at_css("a.graph-name")["href"]).to eq("/ductwork/pipelines/#{run.pipeline_id}?node=Start.a#steps")
      end

      it "links a status label to that node's steps in that status" do
        get path

        expect(graph.at_css("a.graph-label")["href"])
          .to eq("/ductwork/pipelines/#{run.pipeline_id}?node=Start.a&status=failed#steps")
      end

      it "marks the filtered node as selected and links it back to all steps" do
        get path, params: { node: "Start.a" }

        expect(graph.at_css('.graph-node[data-selected="true"] a.graph-name')["href"])
          .to eq("/ductwork/pipelines/#{run.pipeline_id}#steps")
      end

      it "escapes class names from the definition" do
        definition[:edges]["Start.a"][:klass] = "<script>alert(1)</script>"
        run.update!(definition: definition.to_json)

        get path

        expect(response.body).not_to include("<script>alert(1)</script>")
      end

      it "omits the graph for a definition with no nodes" do
        run.update!(definition: "{}")

        get path

        expect(graph).to be_nil
      end
    end

    context "when filtering steps" do
      let(:run) { create(:run) }

      def step_with_job(**attributes)
        create(:step, run:, **attributes).tap { |step| create(:job, step:) }
      end

      it "filters by step klass" do
        match = step_with_job(klass: "StepA", status: "completed")
        other = step_with_job(klass: "StepB", status: "completed")

        get "/ductwork/pipelines/#{run.pipeline_id}", params: { klass: "StepA" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(match.id)
        expect(response.body).not_to include(other.id)
      end

      it "filters by node when the same klass appears at two nodes" do
        match = step_with_job(klass: "StepA", node: "StepA.aaaa", status: "completed")
        other = step_with_job(klass: "StepA", node: "StepA.bbbb", status: "completed")

        get "/ductwork/pipelines/#{run.pipeline_id}", params: { node: "StepA.aaaa" }

        expect(response.body).to include(match.id)
        expect(response.body).not_to include(other.id)
      end

      it "filters by status" do
        match = step_with_job(status: "failed")
        other = step_with_job(status: "completed")

        get "/ductwork/pipelines/#{run.pipeline_id}", params: { status: "failed" }

        expect(response.body).to include(match.id)
        expect(response.body).not_to include(other.id)
      end

      it "shows the filtered count against the run's total" do
        step_with_job(status: "failed")
        step_with_job(status: "completed")

        get "/ductwork/pipelines/#{run.pipeline_id}", params: { status: "failed" }

        expect(response.body).to include("Steps (1 of 2)")
      end

      it "keeps filters on the pagination links" do
        27.times { step_with_job(node: "StepA.aaaa", status: "failed") }

        get "/ductwork/pipelines/#{run.pipeline_id}", params: { node: "StepA.aaaa", status: "failed" }

        next_path = Nokogiri::HTML(response.body).at_css("a.pager-link[rel=next]")["href"]
        expect(Rack::Utils.parse_query(URI(next_path).query))
          .to eq("node" => "StepA.aaaa", "status" => "failed", "page" => "1")
      end
    end

    context "when paginating steps" do
      let(:run) { create(:run) }
      let(:started_at) { Time.current }
      let!(:steps) do
        Array.new(27) do
          create(:step, run: run, started_at: started_at, status: "completed").tap { |step| create(:job, step:) }
        end
      end

      def pager_links
        Nokogiri::HTML(response.body).css(".pager-link")
      end

      it "shows the position on the first page and enables only next" do
        get "/ductwork/pipelines/#{run.pipeline_id}"

        expect(response.body).to include("Showing 1-25 of 27")
        expect(pager_links.first["aria-disabled"]).to eq("true")
        expect(pager_links.last["href"]).to be_present
      end

      it "disables next on the last page" do
        get "/ductwork/pipelines/#{run.pipeline_id}", params: { page: 1 }

        expect(response.body).to include("Showing 26-27 of 27")
        expect(pager_links.last["aria-disabled"]).to eq("true")
      end

      it "shows every step exactly once across pages when timestamps tie" do
        seen = [0, 1].flat_map do |page|
          get "/ductwork/pipelines/#{run.pipeline_id}", params: { page: }

          steps.map(&:id).select { |id| response.body.include?(id) }
        end

        expect(seen).to match_array(steps.map(&:id))
      end

      it "breaks timestamp ties by id" do
        tied_run = create(:run)
        later_id = "ffffffff-ffff-7fff-bfff-ffffffffffff"
        earlier_id = "00000000-0000-7000-8000-000000000000"
        [later_id, earlier_id].each do |id|
          step = create(:step, id: id, run: tied_run, started_at: started_at, status: "completed")
          create(:job, step:)
        end

        get "/ductwork/pipelines/#{tied_run.pipeline_id}"

        expect(response.body.index(earlier_id)).to be < response.body.index(later_id)
      end

      it "treats a negative page as the first page" do
        get "/ductwork/pipelines/#{run.pipeline_id}", params: { page: -1 }

        expect(response.body).to include("Showing 1-25 of 27")
      end

      it "handles a page past the end" do
        get "/ductwork/pipelines/#{run.pipeline_id}", params: { page: 5 }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Showing 0 of 27")
        expect(pager_links.last["aria-disabled"]).to eq("true")
      end
    end
  end
end
