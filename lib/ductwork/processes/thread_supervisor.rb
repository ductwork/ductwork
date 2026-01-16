# frozen_string_literal: true

module Ductwork
  module Processes
    class ThreadSupervisor
      attr_reader :workers

      def initialize
        @running_context = Ductwork::RunningContext.new
        @workers = []

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

      # TODO: maybe change the whole supervisor interface because this is clunky
      def add_worker(metadata: {}, &block)
        worker = block.call(metadata)
        workers << worker
        worker.start

        Ductwork.logger.debug(
          msg: "Started supervised thread",
          role: :thread_supervisor,
          thread: worker.name
        )
      end

      def run
        Ductwork.logger.debug(
          msg: "Entering main work loop",
          role: :thread_supervisor,
          pid: ::Process.pid
        )

        while running_context.running?
          sleep(Ductwork.configuration.supervisor_polling_timeout)
          check_worker_health
        end

        shutdown
      end

      private

      attr_reader :running_context

      def check_worker_health
        Ductwork.logger.debug(
          msg: "Checking workers are alive",
          role: :thread_supervisor
        )

        workers.each do |worker|
          if !worker.alive?
            worker.restart

            Ductwork.logger.info(
              msg: "Restarted supervised thread",
              role: :thread_supervisor,
              thread: worker.name
            )
          end
        end

        Ductwork.logger.debug(
          msg: "Checked workers are alive",
          role: :thread_supervisor
        )
      end

      def shutdown
        running_context.shutdown!
        log_beginning_shutdown
        workers.each(&:stop)
        await_threads_graceful_shutdown
        kill_remaining_threads
        run_hooks_for(:stop)
      end

      def log_beginning_shutdown
        Ductwork.logger.debug(
          msg: "Beginning shutdown",
          role: :thread_supervisor
        )
      end

      def await_threads_graceful_shutdown
        timeout = Ductwork.configuration.supervisor_shutdown_timeout
        deadline = Time.current + timeout

        Ductwork.logger.debug(
          msg: "Attempting graceful shutdown",
          role: :thread_supervisor
        )
        while Time.current < deadline && workers.any?(&:alive?)
          workers.each do |worker|
            break if Time.current > deadline

            # TODO: Maybe make this configurable. If there's a ton of workers
            # it may not even get to the "later" ones depending on the timeout
            worker.join(1)
          end
        end
      end

      def kill_remaining_threads
        workers.each do |worker|
          if worker.alive?
            worker.kill
            Ductwork.logger.debug(
              msg: "Killed supervised thread",
              role: :thread_supervisor,
              thread: worker.name
            )
          end
        end
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
