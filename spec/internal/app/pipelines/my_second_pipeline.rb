# frozen_string_literal: true

class MySecondPipeline < Ductwork::Pipeline
  define do |pipeline|
    pipeline.start(MyFirstStep).chain(MySecondStep).chain(MyThirdStep)
  end
end
