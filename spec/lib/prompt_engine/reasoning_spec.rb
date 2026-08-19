require "rails_helper"

RSpec.describe PromptEngine::Reasoning do
  # vivopoint's config/config.yml prompt_engine.options_for_model_select (19 ids).
  # This is the table that catches the `/^gpt-5/`-matches-`gpt-5.6`/`gpt-5.4`
  # anchoring trap: a naive pattern would silently hand GPT-5.6/GPT-5.4 the
  # GPT-5 value list instead of leaving them correctly matched by their own,
  # more specific family entries.
  EXPECTED_FAMILY_FOR_MODEL = {
    "claude-opus-5" => nil,
    "claude-sonnet-5" => nil,
    "claude-opus-4-8" => "claude-opus-4-8",
    "claude-sonnet-4-6" => "claude-sonnet-4-6",
    "claude-haiku-4-5" => "claude-haiku-4-5",
    "gpt-5.6-sol" => "gpt-5.6",
    "gpt-5.6-terra" => "gpt-5.6",
    "gpt-5.6-luna" => "gpt-5.6",
    "gpt-5.4" => "gpt-5.4",
    "gpt-5.4-mini" => "gpt-5.4",
    "gpt-5.4-nano" => "gpt-5.4",
    "gpt-5" => "gpt-5",
    "gpt-5-mini" => "gpt-5",
    "gpt-5-nano" => "gpt-5",
    "gpt-4.1" => nil,
    "gpt-4.1-mini" => nil,
    "gpt-4.1-nano" => nil,
    "gpt-4o" => nil,
    "gpt-4o-mini" => nil
  }.freeze

  describe "#values_for" do
    it "returns the exact value list for gpt-5.6" do
      expect(described_class.values_for("gpt-5.6-sol")).to eq(%w[none low medium high xhigh max])
    end

    it "returns the exact value list for gpt-5.4" do
      expect(described_class.values_for("gpt-5.4-mini")).to eq(%w[none low medium high xhigh])
    end

    it "returns the exact value list for gpt-5" do
      expect(described_class.values_for("gpt-5-nano")).to eq(%w[minimal low medium high])
    end

    it "returns the exact value list for claude-opus-4-8 (effort-only)" do
      expect(described_class.values_for("claude-opus-4-8")).to eq(%w[low medium high xhigh max])
    end

    it "returns the exact value list for claude-sonnet-4-6 (effort, budget available but unused)" do
      expect(described_class.values_for("claude-sonnet-4-6")).to eq(%w[low medium high max])
    end

    it "returns the exact value list for claude-haiku-4-5 (budget-only)" do
      expect(described_class.values_for("claude-haiku-4-5")).to eq(%w[low medium high])
    end

    it "returns an empty array for a model that supports no reasoning" do
      expect(described_class.values_for("gpt-4o")).to eq([])
    end

    it "returns an empty array for a hidden Claude 5 id" do
      expect(described_class.values_for("claude-opus-5")).to eq([])
    end

    it "returns an empty array for nil" do
      expect(described_class.values_for(nil)).to eq([])
    end
  end

  describe "#family_for" do
    EXPECTED_FAMILY_FOR_MODEL.each do |model_id, expected_family|
      it "maps #{model_id.inspect} to #{expected_family.inspect}" do
        expect(described_class.family_for(model_id)).to eq(expected_family)
      end
    end
  end

  describe "#supported?" do
    it "is true for a reasoning-capable model" do
      expect(described_class.supported?("gpt-5.6-sol")).to be true
    end

    it "is false for a non-reasoning model" do
      expect(described_class.supported?("gpt-4o")).to be false
    end
  end

  describe "#resolve" do
    it "returns nil for a model that supports no reasoning, regardless of stored value" do
      expect(described_class.resolve("gpt-4o", "high")).to be_nil
      expect(described_class.resolve("gpt-4o", nil)).to be_nil
    end

    it "defaults to low when nothing is stored" do
      expect(described_class.resolve("gpt-5.6-sol", nil)).to eq("low")
    end

    it "defaults to low when the stored value is invalid for the model" do
      expect(described_class.resolve("gpt-5-nano", "xhigh")).to eq("low")
    end

    it "passes through a stored value that is still valid for the model" do
      expect(described_class.resolve("gpt-5.6-sol", "xhigh")).to eq("xhigh")
    end

    it "falls back to the family's first value when the default effort itself is unsupported" do
      # claude-haiku-4-5's own values (low/medium/high) do include "low", so
      # exercise a family shape where that would not hold by stubbing a
      # config entry without "low" in its values.
      family_map = PromptEngine.configuration.model_reasoning_options.merge(
        "no-low-family" => {
          pattern: /^no-low-family(-|$)/i,
          mode: "effort",
          values: %w[medium high]
        }
      )
      allow(PromptEngine.configuration).to receive(:model_reasoning_options).and_return(family_map)

      expect(described_class.resolve("no-low-family", nil)).to eq("medium")
    end
  end

  describe "#thinking_args" do
    it "returns nil for a model that supports no reasoning" do
      expect(described_class.thinking_args("gpt-4o", nil)).to be_nil
    end

    it "returns an effort hash for an effort-mode model" do
      expect(described_class.thinking_args("claude-opus-4-8", "high")).to eq({ effort: "high" })
    end

    it "returns a budget hash (token count, not the named level) for a budget-mode model" do
      expect(described_class.thinking_args("claude-haiku-4-5", "medium")).to eq({ budget: 8192 })
    end

    it "resolves a blank stored value to the request-time default before building the hash" do
      expect(described_class.thinking_args("gpt-5.6-sol", nil)).to eq({ effort: "low" })
    end

    it "supports the literal 'none' effort value for GPT-5.4" do
      expect(described_class.thinking_args("gpt-5.4", "none")).to eq({ effort: "none" })
    end
  end

  describe "#select_options" do
    it "returns [label, value] pairs for a reasoning-capable model" do
      expect(described_class.select_options("claude-haiku-4-5")).to eq([
        %w[Low low],
        %w[Medium medium],
        %w[High high]
      ])
    end

    it "returns an empty array for a non-reasoning model" do
      expect(described_class.select_options("gpt-4o")).to eq([])
    end
  end

  describe "#config_for" do
    it "returns the matching entry hash" do
      entry = described_class.config_for("claude-haiku-4-5")

      expect(entry[:mode]).to eq("budget")
      expect(entry[:budgets]).to eq({ "low" => 2048, "medium" => 8192, "high" => 16384 })
    end

    it "returns nil for an unmatched model" do
      expect(described_class.config_for("gpt-4o")).to be_nil
    end
  end

  describe "#client_config" do
    it "returns an array preserving lookup order" do
      config = described_class.client_config

      expect(config).to be_an(Array)
      expect(config.map { |entry| entry[:name] }).to eq(
        PromptEngine.configuration.model_reasoning_options.keys
      )
    end

    it "includes name/pattern/ignore_case/values for each entry" do
      config = described_class.client_config
      gpt56 = config.find { |entry| entry[:name] == "gpt-5.6" }

      expect(gpt56[:pattern]).to eq('^gpt-5\.6(-|$)')
      expect(gpt56[:ignore_case]).to be true
      expect(gpt56[:values]).to eq(%w[none low medium high xhigh max])
    end

    it "produces a JS-safe pattern source with no leftover Ruby-only anchors" do
      described_class.client_config.each do |entry|
        expect(entry[:pattern]).to start_with("^")
        expect(entry[:pattern]).not_to include('\A')
      end
    end
  end

  describe "configuration override" do
    around do |example|
      original = PromptEngine.configuration.model_reasoning_options
      example.run
      PromptEngine.configuration.model_reasoning_options = original
    end

    it "honors a host-app-added family" do
      PromptEngine.configure do |config|
        config.model_reasoning_options["my-llm"] = {
          pattern: /^my-llm(-|$)/i,
          mode: "effort",
          values: %w[low medium high]
        }
      end

      expect(described_class.values_for("my-llm-7b")).to eq(%w[low medium high])
      expect(described_class.family_for("my-llm-7b")).to eq("my-llm")
    end
  end
end
