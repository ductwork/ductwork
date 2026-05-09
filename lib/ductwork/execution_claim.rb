# frozen_string_literal: true

module Ductwork
  class ExecutionClaim
    def initialize(klass, owner_process_id)
      @klass = klass
      @owner_process_id = owner_process_id
      @adapter = Ductwork::Record.connection.adapter_name.downcase
    end

    def latest
      claim = if supports_row_locking?
                RowLockingExecutionClaim
              else
                OptimisticLockingExecutionClaim
              end

      claim.new(klass, owner_process_id).latest
    end

    private

    attr_reader :klass, :owner_process_id, :adapter

    def supports_row_locking?
      adapter.match?(/postgresql/i) ||
        adapter.match?(/mysql2/i) ||
        adapter.match?(/trilogy/i) ||
        adapter.match?(/oracle_enhanced/i)
    end
  end
end
