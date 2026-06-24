# frozen_string_literal: true

module Ductwork
  class Branch < Ductwork::Record # rubocop:todo Metrics/ClassLength
    belongs_to :run, class_name: "Ductwork::Run"
    has_many :transitions,
             class_name: "Ductwork::Transition",
             foreign_key: "branch_id",
             dependent: :destroy
    has_many :steps,
             class_name: "Ductwork::Step",
             foreign_key: "branch_id",
             dependent: :destroy
    has_many :parent_junctions,
             class_name: "Ductwork::BranchLink",
             foreign_key: "child_branch_id",
             dependent: :destroy
    has_many :child_junctions,
             class_name: "Ductwork::BranchLink",
             foreign_key: "parent_branch_id",
             dependent: :destroy
    has_many :parent_branches, through: :parent_junctions, source: :parent_branch
    has_many :child_branches, through: :child_junctions, source: :child_branch

    validates :last_advanced_at, presence: true
    validates :pipeline_klass, presence: true
    validates :status, presence: true
    validates :started_at, presence: true

    enum :status,
         pending: "pending",
         in_progress: "in_progress",
         waiting: "waiting",
         advancing: "advancing",
         halted: "halted",
         dampened: "dampened",
         completed: "completed"

    enum :halt_reason,
         job_retries_exhausted: "job_retries_exhausted",
         job_crashes_exhausted: "job_crashes_exhausted",
         advancer_crashes_exhausted: "advancer_crashes_exhausted",
         advancer_retries_exhausted: "advancer_retries_exhausted",
         max_fanout_exceeded: "max_fanout_exceeded",
         condition_unmatched: "condition_unmatched",
         transition_invalid: "transition_invalid"

    class TransitionError < StandardError; end

    def self.with_latest_claimed(pipeline_klass)
      branch_claim = Ductwork::BranchClaim.new(pipeline_klass)
      branch = branch_claim.latest

      if branch.present?
        Ductwork::FaultInjection.checkpoint(:after_branch_claim)

        yield branch, branch_claim.transition, branch_claim.advancement

        true
      else
        false
      end
    ensure
      advancement = branch_claim.advancement

      if advancement&.persisted? && advancement.completed_at.nil?
        advancement.thread_crashed!(branch_claim.token)
      end
    end

    # NOTE: claim divergence (the reaper released the branch and another advancer
    # reclaimed it) is the expected outcome of a race, not an error, so the fence
    # treats it as such: it logs and returns `false` rather than raising. Every
    # branch/run mutation must run inside the fence. The row is locked for the
    # block's duration, so divergence can only be observed at entry, never
    # mid-block, and nested fences on the same row always hold. Returns `true`
    # when the block ran, `false` when the claim had diverged.
    def with_claim_fence(&block)
      Ductwork::Record.transaction do
        if self.class.where(id:).lock.pick(:claim_token) == claim_token
          block.call
          true
        else
          log_claim_diverged
          false
        end
      end
    end

    def advance!(transition, advancement)
      step = latest_step
      max_crash = Ductwork.configuration.pipeline_advancer_max_crash

      # NOTE: the crash cap is checked first as the true backstop against a
      # poison branch that repeatedly crashes the advancer process/thread. In a
      # normal failed-step halt no advancer crashes have accrued, so this only
      # fires on a genuine crash loop.
      if advancement.crash_count >= max_crash
        halt_branch_and_resolve_run!(transition, advancement, "advancer_crashes_exhausted")
      elsif step.failed?
        halt_branch_and_resolve_run!(transition, advancement, failed_step_halt_reason(step))
      else
        route_by_edge(transition, advancement)
      end

      # NOTE: this is a no-op unless this advancement just halted the whole run
      run.dispatch_on_halt!
    end

    def complete!
      update!(
        completed_at: Time.current,
        status: "completed",
        claimed_for_advancing_at: nil,
        claim_token: nil,
        last_advanced_at: Time.current
      )

      Ductwork.logger.info(
        msg: "Branch completed",
        branch_id: id,
        role: :pipeline_advancer
      )
    end

    def halt!(halt_reason)
      self.halt_reason = halt_reason

      update!(
        status: "halted",
        claimed_for_advancing_at: nil,
        claim_token: nil,
        last_advanced_at: Time.current
      )

      Ductwork.logger.info(
        msg: "Branch halted",
        branch_id: id,
        role: :pipeline_advancer
      )
    end

    def latest_step
      steps.order(started_at: :desc, id: :desc).limit(1).first
    end

    def release!(expected_token = claim_token)
      Ductwork::Branch
        .where(id: id, claim_token: expected_token, status: :advancing)
        .update_all(
          claimed_for_advancing_at: nil,
          claim_token: nil,
          status: :in_progress,
          last_advanced_at: Time.current
        )
    end

    private

    def log_claim_diverged
      Ductwork.logger.info(
        msg: "Branch claim no longer held",
        branch_id: id,
        pipeline_klass: pipeline_klass
      )
    end

    # NOTE: a failed step exhausted either its error budget (`errored!`) or its
    # crash budget (`crashed!`); both set the step to `failed`, so we read the
    # terminal execution result to report the precise halt reason. yes, another
    # column is prob the better solution here so we don't need to reach in to
    # this data, but the derivation is straightforward, so here we are.
    def failed_step_halt_reason(step)
      if step.terminal_result_type == "process_crashed"
        "job_crashes_exhausted"
      else
        "job_retries_exhausted"
      end
    end

    def halt_branch_and_resolve_run!(transition, advancement, halt_reason)
      with_claim_fence do
        now = Time.current
        advancement.update!(completed_at: now)
        transition.update!(completed_at: now)
        halt!(halt_reason)
        run.resolve_terminal_state!
      end
    rescue StandardError => e
      # NOTE: re-enter the claim fence before mutating branch/advancement state.
      # A non-stale error can be raised above and, before this rescue runs, the
      # reaper could release the branch and another advancer reclaim it (new
      # token). Without the fence this stale advancer would stomp the live claim.
      # A divergence here is benign (another advancer owns the branch now), so we
      # bail rather than let it surface as an advancer crash.
      fenced = with_claim_fence do
        advancement&.update!(
          completed_at: Time.current,
          error_klass: e.class.to_s,
          error_message: e.message,
          error_backtrace: e.backtrace.join("\n")
        )
        release!
      end
      return unless fenced

      Ductwork.logger.error(
        msg: "Branch halt errored",
        branch_id: id,
        error_klass: e.class.to_s,
        error_message: e.message
      )
    end

    def route_by_edge(transition, advancement) # rubocop:todo Metrics
      edge = run.parsed_definition.dig(:edges, latest_step.node)

      if edge.nil? || edge[:to].blank?
        complete_branch_and_pipeline(transition, advancement)
      elsif edge[:type] == "chain"
        chain_branch(edge, transition, advancement)
      elsif edge[:type] == "collapse"
        collapse_branch(edge, transition, advancement)
      elsif edge[:type] == "combine"
        combine_branch(edge, transition, advancement)
      elsif edge[:type] == "converge"
        converge_branch(edge, transition, advancement)
      elsif edge[:type] == "divert"
        divert_branch(edge, transition, advancement)
      elsif edge[:type] == "divide"
        divide_branch(edge, transition, advancement)
      elsif edge[:type] == "expand"
        expand_branch(edge, transition, advancement)
      else
        raise Ductwork::Branch::TransitionError,
              "Invalid transition type `#{edge[:type]}`"
      end
    rescue StandardError => e
      # NOTE: re-enter the claim fence before mutating branch/run terminal state.
      # A non-stale error can be raised above and, before this rescue runs, the
      # reaper could release the branch and another advancer reclaim it (new
      # token). `halt!` is not token-guarded, so without the fence this stale
      # advancer's halt would stomp the live claim and could halt a run another
      # advancer is actively advancing. A divergence here is benign (another
      # advancer owns the branch now), so we bail.
      fenced = with_claim_fence do # rubocop:todo Metrics/BlockLength
        if e.is_a?(Ductwork::Branch::TransitionError) || too_many_failed_attempts?
          latest_step.update!(status: :completed, completed_at: Time.current)

          halt_reason = if e.is_a?(Ductwork::Branch::TransitionError)
                          "transition_invalid"
                        else
                          "advancer_retries_exhausted"
                        end
          now = Time.current
          advancement&.update!(
            completed_at: now,
            error_klass: e.class.to_s,
            error_message: e.message,
            error_backtrace: e.backtrace.join("\n")
          )
          transition.update!(completed_at: now)
          halt!(halt_reason)
          run.resolve_terminal_state!
        else
          # NOTE: since the transaction rolled back from the error the step is
          # back in the `advancing` status so we don't need to set it here.
          advancement&.update!(
            completed_at: Time.current,
            error_klass: e.class.to_s,
            error_message: e.message,
            error_backtrace: e.backtrace.join("\n")
          )
          release!
        end
      end
      return unless fenced

      Ductwork.logger.error(
        msg: "Branch advancement errored",
        branch_id: id,
        error_klass: e.class.to_s,
        error_message: e.message
      )
    end

    def too_many_failed_attempts?
      max = Ductwork.configuration.pipeline_advancer_max_retry
      internal_errors = Ductwork::Advancement::CRASH_ERROR_KLASSES

      # NOTE: crash/abandonment advancements (a process reaped mid-advancement,
      # or a thread killed) are NOT advancer-logic failures and must not consume
      # the retry budget — otherwise a long, legitimately-resuming `expand` /
      # `collapse` fan-out/fan-in (re-claimed once per crash cycle) is falsely
      # halted as `advancer_retries_exhausted`. This mirrors the execution tier,
      # where `crashed!` consumes a separate `crash_count` budget while only
      # `errored!` consumes `retry_count`; crashes are instead capped by
      # `pipeline_advancer_max_crash` (see `advance!`). Only genuine
      # `StandardError`s raised inside the transition logic (which carry their
      # own `error_klass`) count here.
      transitions
        .joins(:advancements)
        .where(in_step_id: latest_step.id)
        .where.not(ductwork_advancements: { error_klass: nil })
        .where.not(ductwork_advancements: { error_klass: internal_errors })
        .count >= max
    end

    def complete_branch_and_pipeline(transition, advancement)
      with_claim_fence do
        latest_step.update!(status: :completed, completed_at: Time.current)
        complete!

        now = Time.current
        advancement.update!(completed_at: now)
        transition.update!(completed_at: now)

        run.resolve_terminal_state!
      end
    end

    def chain_branch(edge, transition, advancement)
      input_arg = Ductwork::Job.find_by(step: latest_step).return_value
      node = edge[:to].sole
      klass = run.parsed_definition.dig(:edges, node, :klass)
      started_at = Time.current

      with_claim_fence do
        latest_step.update!(status: :completed, completed_at: Time.current)
        # NOTE: we stay on the same branch for sequential `chain`-ing
        next_step = steps.create!(
          run: run,
          node: node,
          klass: klass,
          status: "in_progress",
          to_transition: "default",
          started_at: started_at
        )
        Ductwork::Job.enqueue(next_step, input_arg)

        now = Time.current
        advancement.update!(completed_at: now)
        transition.update!(completed_at: now)
        release!
      end
    end

    def collapse_branch(edge, transition, advancement) # rubocop:todo Metrics
      parent_branch_id = parent_junctions.pick(:parent_branch_id)

      with_claim_fence do # rubocop:todo Metrics/BlockLength
        # NOTE: lock the parent branch rather than the whole pipeline run
        # because at-most we're only coordinating across child branches of the
        # parent branch
        Ductwork::Branch.find(parent_branch_id).lock!
        node = latest_step.node
        latest_step.update!(status: :completed, completed_at: Time.current)
        complete!

        sibling_ids = Ductwork::BranchLink
                      .where(parent_branch_id:)
                      .pluck(:child_branch_id)
        all_siblings_completed = Ductwork::Branch
                                 .where(id: sibling_ids)
                                 .where.not(status: :completed)
                                 .none?

        if all_siblings_completed
          input_arg = Ductwork::Job
                      .joins(:step)
                      .where(ductwork_steps: { branch_id: sibling_ids, node: node })
                      .map(&:return_value)
          next_node = edge[:to].sole
          klass = run.parsed_definition.dig(:edges, next_node, :klass)
          started_at = Time.current
          next_branch = run.branches.create!(
            started_at: started_at,
            status: "in_progress",
            last_advanced_at: started_at,
            pipeline_klass: pipeline_klass
          )

          sibling_ids.each do |sibling_id|
            Ductwork::BranchLink
              .create!(parent_branch_id: sibling_id, child_branch_id: next_branch.id)
          end

          next_step = next_branch.steps.create!(
            run: run,
            branch: next_branch,
            node: next_node,
            klass: klass,
            status: "in_progress",
            to_transition: "collapse",
            started_at: started_at
          )
          Ductwork::Job.enqueue(next_step, input_arg)
        end

        now = Time.current
        advancement.update!(completed_at: now)
        transition.update!(completed_at: now)
        run.resolve_terminal_state!
      end
    end

    def combine_branch(edge, transition, advancement) # rubocop:todo Metrics
      parent_branch_id = parent_junctions.pick(:parent_branch_id)

      with_claim_fence do # rubocop:todo Metrics/BlockLength
        # NOTE: lock the parent branch rather than the whole pipeline run
        # because at-most we're only coordinating across child branches of the
        # parent branch
        Ductwork::Branch.find(parent_branch_id).lock!
        latest_step.update!(status: :completed, completed_at: Time.current)
        complete!

        sibling_ids = Ductwork::BranchLink
                      .where(parent_branch_id:)
                      .pluck(:child_branch_id)
        sibling_branches = Ductwork::Branch.where(id: sibling_ids)
        all_siblings_completed = sibling_branches
                                 .where.not(status: :completed)
                                 .none?

        if all_siblings_completed
          final_step_ids = sibling_branches.map { |b| b.latest_step.id }
          input_arg = Ductwork::Job
                      .where(step_id: final_step_ids)
                      .map(&:return_value)
          next_node = edge[:to].sole
          klass = run.parsed_definition.dig(:edges, next_node, :klass)
          started_at = Time.current
          next_branch = run.branches.create!(
            started_at: started_at,
            status: "in_progress",
            last_advanced_at: started_at,
            pipeline_klass: pipeline_klass
          )

          sibling_ids.each do |sibling_id|
            Ductwork::BranchLink
              .create!(parent_branch_id: sibling_id, child_branch_id: next_branch.id)
          end

          next_step = next_branch.steps.create!(
            run: run,
            branch: next_branch,
            node: next_node,
            klass: klass,
            status: "in_progress",
            to_transition: "combine",
            started_at: started_at
          )
          Ductwork::Job.enqueue(next_step, input_arg)
        end

        now = Time.current
        advancement.update!(completed_at: now)
        transition.update!(completed_at: now)
        run.resolve_terminal_state!
      end
    end

    def converge_branch(edge, transition, advancement)
      input_arg = Ductwork::Job.find_by(step: latest_step).return_value
      node = edge[:to].sole
      klass = run.parsed_definition.dig(:edges, node, :klass)
      started_at = Time.current

      with_claim_fence do
        latest_step.update!(status: :completed, completed_at: Time.current)
        # NOTE: we stay on the same branch for `converge`-ing
        next_step = steps.create!(
          run: run,
          node: node,
          klass: klass,
          status: "in_progress",
          to_transition: "converge",
          started_at: started_at
        )
        Ductwork::Job.enqueue(next_step, input_arg)

        now = Time.current
        advancement.update!(completed_at: now)
        transition.update!(completed_at: now)
        release!
      end
    end

    def divert_branch(edge, transition, advancement) # rubocop:disable Metrics/AbcSize
      input_arg = Ductwork::Job.find_by(step: latest_step).return_value
      node = edge[:to][input_arg.to_s] || edge[:to]["otherwise"]
      klass = run.parsed_definition.dig(:edges, node, :klass)
      started_at = Time.current

      if node.nil?
        with_claim_fence do
          latest_step.update!(status: :completed, completed_at: Time.current)
          halt_branch_and_resolve_run!(transition, advancement, "condition_unmatched")
        end
      else
        with_claim_fence do
          latest_step.update!(status: :completed, completed_at: Time.current)
          next_step = steps.create!(
            run: run,
            node: node,
            klass: klass,
            status: "in_progress",
            to_transition: "divert",
            started_at: started_at
          )
          Ductwork::Job.enqueue(next_step, input_arg)

          now = Time.current
          advancement.update!(completed_at: now)
          transition.update!(completed_at: now)
          release!
        end
      end
    end

    def divide_branch(edge, transition, advancement) # rubocop:todo Metrics
      started_at = Time.current
      input_arg = Ductwork::Job.find_by(step: latest_step).return_value
      too_many = edge[:to].tally.any? do |to_klass, count|
        depth = Ductwork
                .configuration
                .steps_max_depth(pipeline: pipeline_klass, step: to_klass)

        depth != -1 && count > depth
      end

      if too_many
        with_claim_fence do
          latest_step.update!(status: :completed, completed_at: Time.current)
          halt_branch_and_resolve_run!(transition, advancement, "max_fanout_exceeded")
        end
      else
        with_claim_fence do
          latest_step.update!(status: :completed, completed_at: Time.current)
          complete!
          edge[:to].each do |to|
            klass = run.parsed_definition.dig(:edges, to, :klass)
            branch = run.branches.create!(
              started_at: started_at,
              status: "in_progress",
              last_advanced_at: started_at,
              pipeline_klass: pipeline_klass
            )

            BranchLink.create!(parent_branch: self, child_branch: branch)
            next_step = branch.steps.create!(
              run: run,
              node: to,
              klass: klass,
              status: "in_progress",
              to_transition: "divide",
              started_at: started_at
            )
            Ductwork::Job.enqueue(next_step, input_arg)
          end

          now = Time.current
          advancement.update!(completed_at: now)
          transition.update!(completed_at: now)
        end
      end
    end

    def expand_branch(edge, transition, advancement)
      next_klass = run.parsed_definition.dig(:edges, edge[:to].sole, :klass)
      return_value = Ductwork::Job.find_by(step: latest_step).return_value
      max_depth = Ductwork.configuration.steps_max_depth(
        pipeline: pipeline_klass,
        step: next_klass
      )

      if max_depth != -1 && return_value.count > max_depth
        with_claim_fence do
          latest_step.update!(status: :completed, completed_at: Time.current)
          halt_branch_and_resolve_run!(transition, advancement, "max_fanout_exceeded")
        end
      elsif return_value.none?
        complete_branch_and_pipeline(transition, advancement)
      else
        bulk_create_steps_and_jobs(edge:, return_value:, transition:, advancement:)
      end
    end

    def bulk_create_steps_and_jobs(edge:, return_value:, transition:, advancement:) # rubocop:todo Metrics
      node = edge[:to].sole
      next_klass = run.parsed_definition.dig(:edges, node, :klass)
      now = Time.current

      with_claim_fence do # rubocop:todo Metrics/BlockLength
        latest_step.update!(status: :completed, completed_at: Time.current)
        complete!

        Array(return_value).each_slice(1_000).each do |batch| # rubocop:todo Metrics/BlockLength
          branch_rows = []
          branch_junction_rows = []
          step_rows = []
          job_rows = []
          execution_rows = []
          availability_rows = []

          batch.each do |value| # rubocop:todo Metrics/BlockLength
            branch_id = SecureRandom.uuid_v7
            branch_junction_id = SecureRandom.uuid_v7
            step_id = SecureRandom.uuid_v7
            job_id = SecureRandom.uuid_v7
            execution_id = SecureRandom.uuid_v7
            availability_id = SecureRandom.uuid_v7

            branch_rows << {
              id: branch_id,
              run_id: run.id,
              pipeline_klass: pipeline_klass,
              status: "in_progress",
              started_at: now,
              last_advanced_at: now,
              created_at: now,
              updated_at: now,
            }
            branch_junction_rows << {
              id: branch_junction_id,
              parent_branch_id: id,
              child_branch_id: branch_id,
              created_at: now,
              updated_at: now,
            }
            step_rows << {
              id: step_id,
              run_id: run.id,
              branch_id: branch_id,
              node: node,
              klass: next_klass,
              status: "in_progress",
              to_transition: "expand",
              started_at: now,
              created_at: now,
              updated_at: now,
            }
            job_rows << {
              id: job_id,
              step_id: step_id,
              input_args: JSON.dump({ args: [value] }),
              klass: next_klass,
              started_at: now,
              created_at: now,
              updated_at: now,
            }
            execution_rows << {
              id: execution_id,
              job_id: job_id,
              retry_count: 0,
              crash_count: 0,
              started_at: now,
              created_at: now,
              updated_at: now,
            }
            availability_rows << {
              id: availability_id,
              execution_id: execution_id,
              pipeline_klass: pipeline_klass,
              started_at: now,
              created_at: now,
              updated_at: now,
            }
          end

          Ductwork::Branch.insert_all!(branch_rows)
          Ductwork::BranchLink.insert_all!(branch_junction_rows)
          Ductwork::Step.insert_all!(step_rows)
          Ductwork::Job.insert_all!(job_rows)
          Ductwork::Execution.insert_all!(execution_rows)
          Ductwork::Availability.insert_all!(availability_rows)

          Ductwork.logger.info(
            msg: "Job batch enqueued",
            count: batch.count,
            job_klass: next_klass
          )
        end

        now = Time.current
        advancement.update!(completed_at: now)
        transition.update!(completed_at: now)
      end
    end
  end
end
