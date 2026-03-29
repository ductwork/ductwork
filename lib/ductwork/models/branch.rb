# frozen_string_literal: true

module Ductwork
  class Branch < Ductwork::Record # rubocop:todo Metrics/ClassLength
    belongs_to :pipeline, class_name: "Ductwork::Pipeline"
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

    class TransitionError < StandardError; end

    def self.with_latest_claimed(pipeline_klass)
      branch_claim = Ductwork::BranchClaim.new(pipeline_klass)
      branch = branch_claim.latest
      succeeded = false

      if branch.present?
        yield branch, branch_claim.transition, branch_claim.advancement

        succeeded = true
      end
    ensure
      if branch.present?
        branch.reload

        attrs = { claimed_for_advancing_at: nil }

        if succeeded
          attrs[:last_advanced_at] = Time.current
        end

        if branch.advancing?
          attrs[:status] = "in_progress"
        end

        branch.update!(attrs)
      end
    end

    def advance!(transition, advancement) # rubocop:todo Metrics
      edge = pipeline.parsed_definition.dig(:edges, latest_step.node)

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
      advancement&.update!(
        completed_at: Time.current,
        error_klass: e.class.to_s,
        error_message: e.message,
        error_backtrace: e.backtrace.join("\n")
      )
    end

    def complete!
      update!(completed_at: Time.current, status: "completed")

      Ductwork.logger.info(
        msg: "Branch completed",
        branch_id: id,
        role: :pipeline_advancer
      )
    end

    def halt!
      halted!

      Ductwork.logger.info(
        msg: "Branch halted",
        branch_id: id,
        role: :pipeline_advancer
      )
    end

    def latest_step
      steps.order(started_at: :desc).limit(1).first
    end

    def release!
      update!(
        claimed_for_advancing_at: nil,
        status: :in_progress,
        last_advanced_at: Time.current
      )
    end

    private

    def complete_branch_and_pipeline(transition, advancement)
      Ductwork::Record.transaction do
        pipeline.lock!
        latest_step.update!(status: :completed, completed_at: Time.current)

        if pipeline.branches.where.not(id:).where.not(status: :completed).none?
          pipeline.complete!
        end

        complete!

        now = Time.current
        advancement.update!(completed_at: now)
        transition.update!(completed_at: now)
      end
    end

    def halt_branch_and_pipeline!(transition, advancement)
      Ductwork::Record.transaction do
        latest_step.update!(status: :completed, completed_at: Time.current)
        pipeline.branches.where(status: %w[advancing in_progress]).each(&:halt!)
        pipeline.halt!

        now = Time.current
        advancement.update!(completed_at: now)
        transition.update!(completed_at: now)
      end
    end

    def chain_branch(edge, transition, advancement)
      input_arg = Ductwork::Job.find_by(step: latest_step).return_value
      node = edge[:to].sole
      klass = pipeline.parsed_definition.dig(:edges, node, :klass)
      started_at = Time.current

      Ductwork::Record.transaction do
        latest_step.update!(status: :completed, completed_at: Time.current)
        # NOTE: we stay on the same branch for `chain`-ing
        next_step = steps.create!(
          pipeline: pipeline,
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
      end
    end

    def collapse_branch(edge, transition, advancement) # rubocop:todo Metrics
      parent_branch_id = parent_junctions.pick(:parent_branch_id)
      node = latest_step.node

      Ductwork::Record.transaction do # rubocop:todo Metrics/BlockLength
        # NOTE: lock the parent branch rather than the whole pipeline because
        # at-most we're only coordinating across child branches of the parent
        Ductwork::Branch.find(parent_branch_id).lock!
        latest_step.update!(status: :completed, completed_at: Time.current)
        complete!

        sibling_ids = Ductwork::BranchLink
                      .where(parent_branch_id:)
                      .pluck(:child_branch_id)
        siblings_completed = Ductwork::Step
                             .where(branch_id: sibling_ids, node: node)
                             .where.not(status: :completed)
                             .none?

        if siblings_completed
          input_arg = Ductwork::Job
                      .joins(:step)
                      .where(ductwork_steps: { branch_id: sibling_ids, node: node })
                      .map(&:return_value)
          next_node = edge[:to].sole
          klass = pipeline.parsed_definition.dig(:edges, next_node, :klass)
          started_at = Time.current
          branch = pipeline.branches.create!(
            started_at: started_at,
            status: "in_progress",
            last_advanced_at: started_at,
            pipeline_klass: pipeline_klass
          )

          sibling_ids.each do |sibling_id|
            Ductwork::BranchLink
              .create!(parent_branch_id: sibling_id, child_branch_id: branch.id)
          end

          next_step = branch.steps.create!(
            pipeline: pipeline,
            branch: branch,
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
      end
    end

    def combine_branch(edge, transition, advancement) # rubocop:todo Metrics
      parent_branch_id = parent_junctions.pick(:parent_branch_id)

      Ductwork::Record.transaction do # rubocop:todo Metrics/BlockLength
        # NOTE: lock the parent branch rather than the whole pipeline because
        # at-most we're only coordinating across child branches of the parent
        Ductwork::Branch.find(parent_branch_id).lock!
        latest_step.update!(status: :completed, completed_at: Time.current)
        complete!

        sibling_ids = Ductwork::BranchLink
                      .where(parent_branch_id:)
                      .pluck(:child_branch_id)
        nodes = Ductwork::Branch.where(id: sibling_ids).map { |b| b.latest_step.node }
        siblings_completed = Ductwork::Step
                             .where(branch_id: sibling_ids, node: nodes)
                             .where.not(status: :completed)
                             .none?

        if siblings_completed
          input_arg = Ductwork::Job
                      .joins(:step)
                      .where(ductwork_steps: { branch_id: sibling_ids, node: nodes })
                      .map(&:return_value)
          next_node = edge[:to].sole
          klass = pipeline.parsed_definition.dig(:edges, next_node, :klass)
          started_at = Time.current
          branch = pipeline.branches.create!(
            started_at: started_at,
            status: "in_progress",
            last_advanced_at: started_at,
            pipeline_klass: pipeline_klass
          )

          sibling_ids.each do |sibling_id|
            Ductwork::BranchLink
              .create!(parent_branch_id: sibling_id, child_branch_id: branch.id)
          end

          next_step = branch.steps.create!(
            pipeline: pipeline,
            branch: branch,
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
      end
    end

    def converge_branch(edge, transition, advancement)
      input_arg = Ductwork::Job.find_by(step: latest_step).return_value
      node = edge[:to].sole
      klass = pipeline.parsed_definition.dig(:edges, node, :klass)
      started_at = Time.current

      Ductwork::Record.transaction do
        latest_step.update!(status: :completed, completed_at: Time.current)
        # NOTE: we stay on the same branch for `converge`-ing
        next_step = steps.create!(
          pipeline: pipeline,
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
      end
    end

    def divert_branch(edge, transition, advancement)
      input_arg = Ductwork::Job.find_by(step: latest_step).return_value
      node = edge[:to][input_arg.to_s] || edge[:to]["otherwise"]
      klass = pipeline.parsed_definition.dig(:edges, node, :klass)
      started_at = Time.current

      if node.nil?
        halt_branch_and_pipeline!(transition, advancement)
      else
        Ductwork::Record.transaction do
          latest_step.update!(status: :completed, completed_at: Time.current)
          next_step = steps.create!(
            pipeline: pipeline,
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
        end
      end
    end

    def divide_branch(edge, transition, advancement) # rubocop:todo Metrics/AbcSize
      started_at = Time.current
      input_arg = Ductwork::Job.find_by(step: latest_step).return_value
      too_many = edge[:to].tally.any? do |to_klass, count|
        depth = Ductwork
                .configuration
                .steps_max_depth(pipeline: pipeline_klass, step: to_klass)

        depth != -1 && count > depth
      end

      if too_many
        halt_branch_and_pipeline!(transition, advancement)
      else
        Ductwork::Record.transaction do
          latest_step.update!(status: :completed, completed_at: Time.current)
          complete!
          edge[:to].each do |to|
            klass = pipeline.parsed_definition.dig(:edges, to, :klass)
            branch = pipeline.branches.create!(
              started_at: started_at,
              status: "in_progress",
              last_advanced_at: started_at,
              pipeline_klass: pipeline_klass
            )

            BranchLink.create!(parent_branch: self, child_branch: branch)
            next_step = branch.steps.create!(
              pipeline: pipeline,
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
      next_klass = pipeline.parsed_definition.dig(:edges, edge[:to].sole, :klass)
      return_value = Ductwork::Job.find_by(step: latest_step).return_value
      max_depth = Ductwork.configuration.steps_max_depth(
        pipeline: pipeline_klass,
        step: next_klass
      )

      if max_depth != -1 && return_value.count > max_depth
        halt_branch_and_pipeline!(transition, advancement)
      elsif return_value.none?
        complete_branch_and_pipeline(transition, advancement)
      else
        bulk_create_steps_and_jobs(edge:, return_value:, transition:, advancement:)
      end
    end

    def bulk_create_steps_and_jobs(edge:, return_value:, transition:, advancement:) # rubocop:todo Metrics
      node = edge[:to].sole
      next_klass = pipeline.parsed_definition.dig(:edges, node, :klass)
      now = Time.current

      Ductwork::Record.transaction do # rubocop:todo Metrics/BlockLength
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
              pipeline_id: pipeline.id,
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
              pipeline_id: pipeline.id,
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
