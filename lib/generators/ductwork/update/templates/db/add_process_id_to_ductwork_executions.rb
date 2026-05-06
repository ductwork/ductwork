# frozen_string_literal: true

class AddProcessIdToDuctworkExecution < Ductwork::Migration
  def up
    options = if postgresql?
                {
                  type: uuid_column_type,
                  index: true,
                  null: true,
                  foreign_key: { to_table: :ductwork_processes },
                }
              else
                {
                  type: uuid_column_type,
                  limit: 36,
                  index: true,
                  null: true,
                  foreign_key: { to_table: :ductwork_processes },
                }
              end

    add_reference :ductwork_executions, :process, **options

    Ductwork::Execution.find_each do |execution|
      execution.update!(process: execution.availability.process)
    end
  end

  def down
    remove_reference :ductwork_executions,
                     :process,
                     foreign_key: { to_table: :ductwork_processes },
                     index: true
  end
end
