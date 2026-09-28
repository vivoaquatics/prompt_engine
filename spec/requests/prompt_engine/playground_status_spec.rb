require "rails_helper"

module PromptEngine
  RSpec.describe "Playground with status filtering", type: :request do
    include Engine.routes.url_helpers

    let!(:active_prompt) do
      create(:prompt,
        name: "Active Test Prompt",
        slug: "test-prompt",
        content: "Active: {{message}}",
        status: "active"
      ).tap(&:sync_parameters!)
    end

    let!(:draft_prompt) do
      create(:prompt,
        name: "Draft Test Prompt",
        slug: "draft-test-prompt",
        content: "Draft: {{message}}",
        status: "draft"
      ).tap(&:sync_parameters!)
    end

    describe "GET playground with status-filtered prompts" do
      it "can access active prompts playground" do
        get playground_prompt_path(active_prompt)
        expect(response).to be_successful
        expect(response.body).to include("Active Test Prompt")
      end

      it "can access draft prompts playground" do
        get playground_prompt_path(draft_prompt)
        expect(response).to be_successful
        expect(response.body).to include("Draft Test Prompt")
      end
    end

    describe "POST execute in playground" do
      before do
        # Mock RubyLLM
        allow_any_instance_of(PlaygroundExecutor).to receive(:require).with("ruby_llm")

        # Mock the chat response
        chat_mock = instance_double(RubyLLM::Chat)
        response_mock = double("Response", content: "Test response", input_tokens: 5, output_tokens: 5)

        stub_ruby_llm_context!(chat_double: chat_mock)
        allow(chat_mock).to receive(:with_temperature).and_return(chat_mock)
        allow(chat_mock).to receive(:with_instructions).and_return(chat_mock)
        allow(chat_mock).to receive(:ask).and_return(response_mock)
      end

      it "executes draft prompts in playground" do
        post playground_prompt_path(draft_prompt), params: {
          provider: "openai",
          api_key: "test-key",
          parameters: { message: "Hello" }
        }

        expect(response).to be_successful
        result = PlaygroundRunResult.last
        expect(result.prompt_version.prompt).to eq(draft_prompt)
      end

      it "executes active prompts in playground" do
        post playground_prompt_path(active_prompt), params: {
          provider: "openai",
          api_key: "test-key",
          parameters: { message: "World" }
        }

        expect(response).to be_successful
        result = PlaygroundRunResult.last
        expect(result.prompt_version.prompt).to eq(active_prompt)
      end
    end

    describe "Playground UI considerations" do
      it "shows prompt status in playground header" do
        get playground_prompt_path(draft_prompt)

        # The playground should indicate this is a draft
        expect(response.body).to include("Draft Test Prompt")
        expect(response.body).to include(draft_prompt.status.capitalize)
      end
    end
  end
end
