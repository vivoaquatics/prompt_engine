# This migration comes from prompt_engine (originally 20260818234952)
class AddReasoningEffortToPromptEngine < ActiveRecord::Migration[8.0]
  def change
    add_column :prompt_engine_prompts, :reasoning_effort, :string
    add_column :prompt_engine_prompt_versions, :reasoning_effort, :string
    add_column :prompt_engine_playground_run_results, :reasoning_effort, :string
  end
end
