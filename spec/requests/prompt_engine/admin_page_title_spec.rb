require "rails_helper"

module PromptEngine
  RSpec.describe "Admin page title", type: :request do
    it "prepends the prompt name on a prompt page" do
      prompt = Prompt.create!(name: "Blu Resolve", slug: "blu-resolve", content: "Hi {{x}}")
      get prompt_engine.prompt_path(prompt)
      expect(response.body).to include("<title>Blu Resolve | PromptEngine Admin</title>")
    end

    it "falls back to the base title when no prompt is present" do
      get prompt_engine.prompts_path
      expect(response.body).to include("<title>PromptEngine Admin</title>")
    end
  end
end
