# Model-family-aware reasoning effort lookup.
#
# `PromptEngine.configuration.model_reasoning_options` maps a family name to
# a pattern/mode/values/budgets entry (see lib/prompt_engine.rb). This module
# is pure lookup logic against that configuration — no state of its own.
module PromptEngine
  module Reasoning
    DEFAULT_EFFORT = "low".freeze

    module_function

    # The matching family entry for a model id, or nil if none match.
    def config_for(model_id)
      PromptEngine.configuration.model_reasoning_options
        .find { |_name, entry| model_id.to_s.match?(entry[:pattern]) }&.last
    end

    # The matching family name for a model id, or nil if none match.
    def family_for(model_id)
      PromptEngine.configuration.model_reasoning_options
        .find { |_name, entry| model_id.to_s.match?(entry[:pattern]) }&.first
    end

    # The allowed reasoning values for a model id. Empty when unsupported.
    def values_for(model_id)
      Array(config_for(model_id)&.fetch(:values, nil))
    end

    def supported?(model_id)
      values_for(model_id).any?
    end

    # The value that should actually be sent for a model, given the stored
    # value: the stored value if still valid, otherwise the default effort
    # (if valid for this model), otherwise the first available value. Returns
    # nil when the model supports no reasoning at all.
    def resolve(model_id, stored_value)
      values = values_for(model_id)
      return nil if values.empty?
      return stored_value if values.include?(stored_value)
      return DEFAULT_EFFORT if values.include?(DEFAULT_EFFORT)

      values.first
    end

    # The keyword arguments to splat into `chat.with_thinking(...)`, or nil
    # when the model supports no reasoning.
    def thinking_args(model_id, stored_value)
      entry = config_for(model_id)
      return nil unless entry

      resolved = resolve(model_id, stored_value)
      return nil unless resolved

      if entry[:mode] == "budget"
        budget = entry.fetch(:budgets, {})[resolved]
        return nil unless budget

        { budget: budget }
      else
        { effort: resolved }
      end
    end

    # [[label, value], ...] for use with `options_for_select`.
    def select_options(model_id)
      values_for(model_id).map { |value| [ value.humanize, value ] }
    end

    # Serializes the family map for client-side JS, preserving lookup order.
    def client_config
      PromptEngine.configuration.model_reasoning_options.map do |name, entry|
        {
          name: name,
          pattern: entry[:pattern].source,
          ignore_case: !(entry[:pattern].options & Regexp::IGNORECASE).zero?,
          values: entry[:values]
        }
      end
    end
  end
end
