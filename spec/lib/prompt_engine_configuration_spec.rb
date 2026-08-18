require "rails_helper"

RSpec.describe PromptEngine do
  # NOTE: this block has a known, pre-existing global-state leak — it mutates
  # options_for_model_select and never restores it. Accepted as a follow-up rather than
  # fixed here (tracked as CVP-1821). Left as-is intentionally; do not "helpfully" fix it.
  describe "configure" do
    it "yields the configuration object" do
      PromptEngine.configure do |config|
        config.options_for_model_select = [
          ["Custom Model 1", "custom-model-1"]
        ]
      end

      expect(
        PromptEngine.configuration.options_for_model_select
      ).to eq([["Custom Model 1", "custom-model-1"]])
    end
  end

  describe "#options_for_model_select" do
    # Asserted against a fresh Configuration instance (not the process-wide
    # PromptEngine.configuration singleton), which is deliberately immune to the
    # "configure" block's known leak above — these examples test the class default,
    # not whatever the singleton was last mutated to under RSpec's random ordering.
    let(:default_ids) { PromptEngine.configuration.class.new.options_for_model_select.map(&:last) }

    it "includes the ids added to fix the playground_executor_spec regression" do
      expect(default_ids).to include("gpt-4o", "claude-3-5-sonnet-20241022", "claude-3-opus-20240229")
    end

    it "does not include the CVP-1796 ticket models (vivopoint-only, not a gem default)" do
      expect(default_ids).not_to include(
        "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "claude-opus-5", "claude-sonnet-5"
      )
    end
  end

  describe "#model_provider_patterns" do
    around do |example|
      original = PromptEngine.configuration.model_provider_patterns
      example.run
      PromptEngine.configuration.model_provider_patterns = original
    end

    it "defaults to patterns for the built-in providers" do
      patterns = PromptEngine.configuration.model_provider_patterns

      expect(patterns.keys).to contain_exactly("anthropic", "openai")
      expect("claude-3-opus").to match(patterns["anthropic"])
      expect("gpt-4").to match(patterns["openai"])
    end

    it "can be customized to map new model ids to a provider" do
      PromptEngine.configure do |config|
        config.model_provider_patterns["openai"] = /\A(gpt|my-llm)/i
      end

      expect("my-llm-7b").to match(PromptEngine.configuration.model_provider_patterns["openai"])
    end

    it "matches the CVP-1796 GPT-5.6 ids through the untouched openai pattern" do
      patterns = PromptEngine.configuration.model_provider_patterns

      expect("gpt-5.6-sol").to match(patterns["openai"])
    end

    it "matches the CVP-1796 Claude 5 ids through the untouched anthropic pattern" do
      patterns = PromptEngine.configuration.model_provider_patterns

      expect("claude-opus-5").to match(patterns["anthropic"])
    end
  end
end
