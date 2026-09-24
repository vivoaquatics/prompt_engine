require "rails_helper"

# The "column missing" state is simulated by stubbing .column_names rather
# than actually dropping/re-adding the real `reasoning_effort` column at
# runtime (which would require live DDL against the test DB and careful
# cleanup around every other spec sharing that connection). Stubbing the one
# method the guard actually consults is a faithful, much lower-risk way to
# exercise the same code paths.
RSpec.describe PromptEngine::ReasoningColumnGuard do
  after do
    # Always leave the class's memo in its real, positive state for every
    # other spec that runs in this process afterward.
    PromptEngine::Prompt.reset_column_information
  end

  describe ".reasoning_effort_column?" do
    it "is true against the real (migrated) schema" do
      expect(PromptEngine::Prompt.reasoning_effort_column?).to be true
    end

    it "memoizes only the positive result, so it stays true on repeated calls" do
      PromptEngine::Prompt.reasoning_effort_column?

      allow(PromptEngine::Prompt).to receive(:column_names).and_return(
        PromptEngine::Prompt.column_names - [ "reasoning_effort" ]
      )

      # Already-cached true is returned without re-consulting column_names.
      expect(PromptEngine::Prompt.reasoning_effort_column?).to be true
    end
  end

  describe "degraded (column reported missing) behavior" do
    # Create the prompt (a genuine write, through the real column) BEFORE
    # stubbing column_names away - otherwise the factory's own
    # `reasoning_effort: "high"` write would itself be silently no-op'd by
    # the guard, and the test would no longer be exercising "already had a
    # value, then the column disappeared mid-process".
    let!(:prompt) { create(:prompt, model: "gpt-5.6-sol", reasoning_effort: "high") }

    before do
      PromptEngine::Prompt.instance_variable_set(:@reasoning_effort_column, nil)
      allow(PromptEngine::Prompt).to receive(:column_names).and_return(
        PromptEngine::Prompt.column_names - [ "reasoning_effort" ]
      )
    end

    it "reports the column as unavailable, and does not cache that as permanent" do
      expect(PromptEngine::Prompt.reasoning_effort_column?).to be false
      # Calling it again (without a reset in between) still re-derives false,
      # rather than a permanently cached negative.
      expect(PromptEngine::Prompt.reasoning_effort_column?).to be false
    end

    it "reads as nil instead of raising" do
      expect(prompt.reload.reasoning_effort).to be_nil
    end

    it "no-ops on write instead of raising, leaving the underlying attribute untouched" do
      prompt.reload.reasoning_effort = "low"

      expect(prompt.reasoning_effort).to be_nil
      expect(prompt.read_attribute(:reasoning_effort)).to eq("high")
    end
  end

  describe "self-healing after reset_column_information" do
    it "starts reporting true again once the column is reachable and the cache is reset" do
      PromptEngine::Prompt.instance_variable_set(:@reasoning_effort_column, nil)
      allow(PromptEngine::Prompt).to receive(:column_names).and_return(
        PromptEngine::Prompt.column_names - [ "reasoning_effort" ]
      )
      expect(PromptEngine::Prompt.reasoning_effort_column?).to be false

      allow(PromptEngine::Prompt).to receive(:column_names).and_call_original
      PromptEngine::Prompt.reset_column_information

      expect(PromptEngine::Prompt.reasoning_effort_column?).to be true

      prompt = create(:prompt, model: "gpt-5.6-sol", reasoning_effort: "high")
      prompt.update!(reasoning_effort: "low")

      expect(prompt.reload.reasoning_effort).to eq("low")
    end
  end
end
