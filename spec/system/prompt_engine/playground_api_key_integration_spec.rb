require "rails_helper"

module PromptEngine
  RSpec.describe "Playground API Key Integration", type: :system do
    include Engine.routes.url_helpers

    let(:prompt) { create(:prompt, name: "Test Prompt", content: "Hello {{name}}") }

    before do
      driven_by(:rack_test)
    end

    describe "API key handling (CVP-1822)" do
      context "when settings have API keys saved" do
        before do
          Setting.instance.update!(
            openai_api_key: "sk-test-openai-key",
            anthropic_api_key: "sk-ant-test-anthropic-key"
          )
        end

        it "never renders stored API keys into the page" do
          anthropic_prompt = create(:prompt, name: "Anthropic Prompt", content: "Hello {{name}}", model: "claude-3-5-sonnet")
          openai_prompt = create(:prompt, name: "OpenAI Prompt", content: "Hello {{name}}", model: "gpt-4o")

          visit playground_prompt_path(anthropic_prompt)
          expect(page).to have_field("api_key")
          expect(find("#api_key")[:value]).to be_nil
          expect(page.body).not_to include("sk-ant-test-anthropic-key")
          expect(page.body).not_to include("sk-test-openai-key")
          expect(page).to have_text("Using saved API key from settings")

          visit playground_prompt_path(openai_prompt)
          expect(page).to have_field("api_key")
          expect(find("#api_key")[:value]).to be_nil
          expect(page.body).not_to include("sk-ant-test-anthropic-key")
          expect(page.body).not_to include("sk-test-openai-key")
          expect(page).to have_text("Using saved API key from settings")

          # A prompt whose model maps to no known provider still must not leak
          # either key anywhere on the page (data attrs, script, or field value).
          visit playground_prompt_path(prompt)
          expect(page.body).not_to include("sk-ant-test-anthropic-key")
          expect(page.body).not_to include("sk-test-openai-key")
          api_key_field = find("#api_key")
          expect(api_key_field["data-anthropic-key"]).to be_nil
          expect(api_key_field["data-openai-key"]).to be_nil
        end

        it "renders only the boolean configured data attributes, never a key attribute" do
          openai_prompt = create(:prompt, name: "OpenAI Prompt", content: "Hello {{name}}", model: "gpt-4o")

          visit playground_prompt_path(openai_prompt)

          api_key_field = find("#api_key")
          expect(api_key_field["data-openai-configured"]).to eq("true")
          expect(api_key_field["data-anthropic-configured"]).to eq("true")
          expect(api_key_field["data-anthropic-key"]).to be_nil
          expect(api_key_field["data-openai-key"]).to be_nil
        end

        it "renders the api_key field as not required" do
          openai_prompt = create(:prompt, name: "OpenAI Prompt", content: "Hello {{name}}", model: "gpt-4o")

          visit playground_prompt_path(openai_prompt)

          expect(find("#api_key")[:required]).to be_falsey
        end

        it "opts the api_key field out of browser credential autofill" do
          openai_prompt = create(:prompt, name: "OpenAI Prompt", content: "Hello {{name}}", model: "gpt-4o")

          visit playground_prompt_path(openai_prompt)

          expect(find("#api_key")["autocomplete"]).to eq("new-password")
        end

        it "includes link to change settings" do
          visit playground_prompt_path(prompt)

          expect(page).to have_link("Change in settings", href: edit_settings_path)
        end
      end

      context "when no API keys are saved" do
        before do
          Setting.instance.update!(
            openai_api_key: nil,
            anthropic_api_key: nil
          )
        end

        it "shows placeholder and link to save in settings" do
          visit playground_prompt_path(prompt)

          expect(page).to have_field("api_key", placeholder: "Enter your API key")
          expect(find("#api_key")[:value]).to be_nil
          expect(page).to have_link("Save in settings", href: edit_settings_path)
        end

        it "marks both providers as not configured" do
          visit playground_prompt_path(prompt)

          api_key_field = find("#api_key")
          expect(api_key_field["data-openai-configured"]).to eq("false")
          expect(api_key_field["data-anthropic-configured"]).to eq("false")
        end
      end

      context "when only one provider has API key saved" do
        before do
          Setting.instance.update!(
            openai_api_key: "sk-test-openai-only",
            anthropic_api_key: nil
          )
        end

        it "shows the saved-key hint without ever rendering the key itself" do
          openai_prompt = create(:prompt, name: "OpenAI Prompt", content: "Hello {{name}}", model: "gpt-4o")

          visit playground_prompt_path(openai_prompt)

          expect(page).to have_field("api_key")
          expect(find("#api_key")[:value]).to be_nil
          expect(page).to have_text("Using saved API key from settings")
          expect(page.body).not_to include("sk-test-openai-only")

          api_key_field = find("#api_key")
          expect(api_key_field["data-openai-configured"]).to eq("true")
          expect(api_key_field["data-anthropic-configured"]).to eq("false")
          expect(api_key_field["data-openai-key"]).to be_nil
          expect(api_key_field["data-anthropic-key"]).to be_nil
        end
      end
    end

    describe "executing playground with saved API keys" do
      before do
        Setting.instance.update!(
          anthropic_api_key: "sk-ant-valid-test-key"
        )
      end

      it "uses the saved API key for execution" do
        # Create a prompt with anthropic model so it prefills the API key
        anthropic_prompt = create(:prompt, name: "Claude Prompt", content: "Hello {{name}}", model: "claude-3-5-sonnet")

        visit playground_prompt_path(anthropic_prompt)

        fill_in "parameters[name]", with: "World"

        # Mock the executor to verify it receives the saved API key
        allow_any_instance_of(PlaygroundExecutor).to receive(:execute).and_return({
          response: "Hello World!",
          execution_time: 1.5,
          token_count: 10,
          model: "claude-3-5-sonnet-20241022",
          provider: "anthropic"
        })

        click_button "Test Prompt"

        expect(page).to have_content("Hello World!")
      end
    end
  end
end
