# Guards every AR-level touch point of `reasoning_effort` against the
# "gem bumped before migration ran" sequencing risk: a host app can update
# to a prompt_engine revision that expects the `reasoning_effort` column
# before it has actually run `db:migrate` for the new migration. Without a
# guard, every reasoning_effort-touching code path (model
# validations/callbacks, RenderedPrompt, the prompts views, PlaygroundExecutor)
# raises NoMethodError / ActiveModel::UnknownAttributeError the moment it
# reads or writes the column - taking down the entire prompts UI and
# `PromptEngine.render`, not just this one feature.
#
# `read_attribute`/`write_attribute` (rather than `super`) are used
# deliberately here: they're unconditionally defined on every
# ActiveRecord::Base subclass, so this guard can't be accidentally shadowed
# (or itself shadowed) by ActiveRecord's own lazily-generated attribute
# methods depending on module include order.
module PromptEngine
  module ReasoningColumnGuard
    extend ActiveSupport::Concern

    class_methods do
      # Memoized per-class, but ONLY the positive result is cached. A
      # negative result must never be cached permanently: a process that
      # boots before the migration runs would otherwise silently discard
      # every `reasoning_effort` write for the rest of that process's life,
      # even after the column is added and `reset_column_information` is
      # called elsewhere. Once true, `column_names` (backed by Rails' own
      # schema cache) is never consulted again for this class unless
      # `reset_column_information` (overridden below) clears the memo.
      def reasoning_effort_column?
        return true if @reasoning_effort_column

        @reasoning_effort_column = column_names.include?("reasoning_effort")
      end

      # Rails calls this whenever it invalidates a model's schema info
      # (e.g. after a migration runs in the same process, or explicitly in
      # a console/test). Clear our own memo in lockstep so a subsequent
      # `reasoning_effort_column?` call re-checks rather than staying
      # permanently false.
      def reset_column_information
        remove_instance_variable(:@reasoning_effort_column) if defined?(@reasoning_effort_column)
        super
      end

      # One-shot (per class) warning so the degraded state is observable in
      # production logs instead of being fully silent - but without
      # spamming a log line on every discarded write.
      def warn_reasoning_effort_column_missing_once
        return if @reasoning_effort_missing_warned

        @reasoning_effort_missing_warned = true
        Rails.logger.warn(
          "[PromptEngine] reasoning_effort column missing on #{table_name} - " \
            "writes to reasoning_effort are being silently discarded until " \
            "pending migrations are run."
        )
      end
    end

    # Returns nil, rather than raising, when the column doesn't exist yet.
    def reasoning_effort
      return nil unless self.class.reasoning_effort_column?

      read_attribute(:reasoning_effort)
    end

    # No-ops, rather than raising, when the column doesn't exist yet - so
    # mass assignment (e.g. strong params permitting :reasoning_effort, or
    # `create!(reasoning_effort: ...)` from the versioning callbacks) degrades
    # silently instead of raising ActiveModel::UnknownAttributeError.
    def reasoning_effort=(value)
      unless self.class.reasoning_effort_column?
        self.class.warn_reasoning_effort_column_missing_once
        return
      end

      write_attribute(:reasoning_effort, value)
    end
  end
end
