# frozen_string_literal: true

require "ductwork/testing"

RSpec.describe Ductwork::Testing do
  describe "have_triggered_pipeline matcher" do
    it "returns true when the pipeline with the given klass is triggered" do
      expect do
        MyPipeline.trigger(1)
      end.to have_triggered_pipeline(MyPipeline)
    end

    it "returns false when no pipelines are triggered" do
      expect do
        MySecondPipeline.trigger(1)
      end.not_to have_triggered_pipeline(MyPipeline)
    end

    it "returns true when the correct count of pipelines triggered matches" do
      expect do
        MyPipeline.trigger(1)
        MyPipeline.trigger(1)
        MyPipeline.trigger(1)
      end.to have_triggered_pipeline(MyPipeline).exactly(3).times
    end
  end

  describe "have_triggered_pipelines matcher" do
    it "returns true when the pipelines with the given klass are triggered" do
      expect do
        MyPipeline.trigger(1)
        MySecondPipeline.trigger(1)
      end.to have_triggered_pipelines(MyPipeline, MySecondPipeline)
    end

    it "returns false when no pipelines are triggered" do
      expect do
        puts
      end.not_to have_triggered_pipelines(MyPipeline, MySecondPipeline)
    end
  end
end
