# frozen_string_literal: true

module Ductwork
  module Processes
    class ThreadSupervisor
      def initialize
        @running_context = Ductwork::RunningContext.new
        @threads = []

        run_hooks_for(:start)

        Signal.trap(:INT) { @running_context.shutdown! }
        Signal.trap(:TERM) { @running_context.shutdown! }
        Signal.trap(:TTIN) do
          Thread.list.each do |thread|
            puts thread.name
            if thread.backtrace
              puts thread.backtrace.join("\n")
            else
              puts "No backtrace to dump"
            end
            puts
          end
        end
      end

      def add_worker(metadata: {}, &block)
        thread = Thread.new do
          block.call(metadata)
        end
        thread.name = metadata[:id]
        threads << { metadata:, block: }

        Ductwork.logger.debug(
          msg: "Started supervised thread with metadata #{metadata}",
          id: metadata[:id]
        )
      end

      def run
        Ductwork.logger.debug(msg: "Entering main work loop", role: :supervisor, pid: ::Process.pid)

        while running_context.running?
          sleep(Ductwork.configuration.supervisor_polling_timeout)
          check_threads
        end

        shutdown
      end

      private

      attr_reader :running_context, :threads

      def check_threads
        Ductwork.logger.debug(msg: "Checking threads are alive", role: :supervisor)

        threads.each do |thread|
          if !thread.alive?
            # TODO: restart but, like, don't spawn "child" threads
          end
        end
      end

      def shutdown
        running_context.shutdown!
        Ductwork.logger.debug(msg: "Beginning shutdown", role: :supervisor)
        run_hooks_for(:stop)
      end

      def run_hooks_for(event)
        Ductwork.hooks[:supervisor].fetch(event, []).each do |block|
          Ductwork.wrap_with_app_executor do
            block.call(self)
          end
        end
      end
    end
  end
end
