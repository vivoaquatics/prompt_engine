module PromptEngine
  class PromptVersion < ApplicationRecord
    self.table_name = "prompt_engine_prompt_versions"

    include PromptEngine::ReasoningColumnGuard

    belongs_to :prompt, class_name: "PromptEngine::Prompt", counter_cache: :versions_count
    has_many :playground_run_results, class_name: "PromptEngine::PlaygroundRunResult", dependent: :destroy
    has_many :eval_runs, class_name: "PromptEngine::EvalRun", dependent: :destroy

    validates :version_number, presence: true,
              numericality: { greater_than: 0 },
              uniqueness: { scope: :prompt_id }
    validates :content, presence: true

    before_validation :set_version_number, on: :create
    validate :ensure_immutability, on: :update

    scope :latest, -> { order(version_number: :desc) }
    scope :chronological, -> { order(created_at: :asc) }

    def restore!
      attrs = to_prompt_attributes

      # A version's own reasoning_effort can be invalid for its own model by
      # the time it's restored: the value may have been valid when this
      # version was created but since removed from model_reasoning_options,
      # or the model's reasoning options may simply differ between the
      # version's snapshot and now. Since Prompt's inclusion validation
      # always fires, sanitize here rather than let a stale/invalid value
      # veto the entire restore (raising ActiveRecord::RecordInvalid and
      # rolling back every other field too).
      unless PromptEngine::Reasoning.values_for(attrs[:model]).include?(attrs[:reasoning_effort])
        attrs[:reasoning_effort] = nil
      end

      # Update the prompt attributes
      prompt.update!(attrs)

      # Check if a version was created (attributes changed)
      latest_version = prompt.versions.first

      if latest_version.created_at > 1.second.ago
        # A new version was just created, update its description
        latest_version.update_column(:change_description, "Restored from version #{version_number}")
      else
        # No version was created (no changes), create one manually
        prompt.versions.create!(
          attrs.merge(
            change_description: "Restored from version #{version_number}"
          )
        )
      end
    end

    def to_prompt_attributes
      {
        content: content,
        system_message: system_message,
        model: model,
        temperature: temperature,
        max_tokens: max_tokens,
        reasoning_effort: reasoning_effort,
        metadata: metadata
      }
    end

    private

    def set_version_number
      return if version_number.present?
      return unless prompt

      max_version = prompt.versions.maximum(:version_number) || 0
      self.version_number = max_version + 1
    end

    def ensure_immutability
      immutable_attributes = %w[content system_message model temperature max_tokens reasoning_effort]
      changed_immutable = (changed & immutable_attributes)

      if changed_immutable.any?
        changed_immutable.each do |attr|
          errors.add(attr, "cannot be changed after creation")
        end
      end
    end
  end
end
