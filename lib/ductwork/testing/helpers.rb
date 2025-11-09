# frozen_string_literal: true

module Ductwork
  module Testing
    module Helpers
      def pipelines_created_around(&block)
        before_ids = Ductwork::Pipeline.ids

        block.call

        after_ids = Ductwork::Pipeline.ids
        ids_delta = after_ids - before_ids

        Ductwork::Pipeline.where(id: ids_delta)
      end
    end
  end
end
