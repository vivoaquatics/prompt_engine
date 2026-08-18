require "rails_helper"

RSpec.describe PromptEngine do
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
  end
end
