# frozen_string_literal: true

RSpec.describe Ductwork::Pipeline do
  describe ".define" do
    let(:klass) do
      Class.new do
        include Ductwork::Pipeline
      end
    end

    it "raises if no definition block is given" do
      expect do
        klass.define
      end.to raise_error(
        described_class::DefinitionError,
        "Definition block must be given"
      )
    end

    it "raises if a pipeline has already been defined on the class" do
      expect do
        klass.define do |pipeline|
          pipeline.start(spy)
        end

        klass.define do |pipeline|
          pipeline.start(spy)
        end
      end.to raise_error(
        described_class::DefinitionError,
        "Pipeline has already been defined"
      )
    end

    it "yields a definition builder to the block" do
      builder = instance_double(Ductwork::DefinitionBuilder, complete!: nil)
      allow(Ductwork::DefinitionBuilder).to receive(:new).and_return(builder)

      expect do |block|
        klass.define(&block)
      end.to yield_with_args(builder)
    end

    it "sets the definition on the class" do
      expect do
        klass.define do |pipeline|
          pipeline.start(spy)
        end
      end.to change(klass, :pipeline_definition).from(nil)
    end

    it "adds the pipeline to whole set of pipelines" do
      expect do
        klass.define do |pipeline|
          pipeline.start(spy)
        end
      end.to change(Ductwork.pipelines, :count).by(1)
      expect(Ductwork.pipelines).to eq([klass.to_s])
    end
  end
end
