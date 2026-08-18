require "rails_helper"

module PromptEngine
  RSpec.describe "Admin stylesheet loading", type: :request do
    it "links each component stylesheet individually (no @import waterfall)" do
      get prompt_engine.prompts_path

      # foundation must come first, overrides last for the cascade to hold.
      links = response.body.scan(/<link[^>]+href="([^"]*\/assets\/prompt_engine\/[^"]+\.css)"/i).flatten
      names = links.map { |h| h[%r{/assets/prompt_engine/(.+?)(?:-[0-9a-f]+)?\.css}, 1] }

      expect(names.first).to eq("foundation")
      expect(names.last).to eq("components/_test_runs")
      expect(names).to include("forms", "sidebar", "overrides")
      # The old single bundle must no longer be linked.
      expect(response.body).not_to match(%r{/assets/prompt_engine/application(-[0-9a-f]+)?\.css})
    end
  end
end
