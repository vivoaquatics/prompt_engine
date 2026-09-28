require "rails_helper"

module PromptEngine
  RSpec.describe "Playground", type: :request do
    # Include engine routes helpers
    include Engine.routes.url_helpers
    let(:prompt) { create(:prompt, content: "Tell me about {{topic}} in {{style}} style") }

    describe "GET /prompt_engine/prompts/:id/playground" do
      context "when prompt exists" do
        it "returns a successful response" do
          get playground_prompt_path(prompt)
          expect(response).to be_successful
        end

        it "displays the playground interface" do
          get playground_prompt_path(prompt)
          expect(response.body).to include("Test Prompt")
        end

        it "displays the prompt content" do
          get playground_prompt_path(prompt)
          expect(response.body).to include("Prompt Parameters")
        end

        it "displays the prompt's parameters" do
          get playground_prompt_path(prompt)
          expect(response.body).to include("topic")
          expect(response.body).to include("style")
        end

        it "displays model selection" do
          get playground_prompt_path(prompt)
          expect(response.body).to include("Model")
          expect(response.body).to include("gpt-4")
        end
      end

      context "API key exposure (CVP-1822)" do
        before do
          PromptEngine::Setting.instance.update!(
            openai_api_key: "sk-test-openai-key",
            anthropic_api_key: "sk-ant-test-anthropic-key"
          )
        end

        it "never renders either stored provider key into the page" do
          get playground_prompt_path(prompt)

          expect(response.body).not_to include("sk-test-openai-key")
          expect(response.body).not_to include("sk-ant-test-anthropic-key")
        end

        it "never renders a data-anthropic-key or data-openai-key attribute" do
          get playground_prompt_path(prompt)

          expect(response.body).not_to include("data-anthropic-key")
          expect(response.body).not_to include("data-openai-key")
        end

        it "renders only the boolean configured flags" do
          get playground_prompt_path(prompt)

          expect(response.body).to include("data-anthropic-configured")
          expect(response.body).to include("data-openai-configured")
        end

        it "never renders either key for a prompt whose model maps to the default provider" do
          openai_prompt = create(:prompt, model: "gpt-4o", content: "Hello {{name}}")

          get playground_prompt_path(openai_prompt)

          expect(response.body).not_to include("sk-test-openai-key")
          expect(response.body).not_to include("sk-ant-test-anthropic-key")
        end
      end

      context "when prompt does not exist" do
        it "raises ActiveRecord::RecordNotFound" do
          # In request specs, we don't use expect to raise_error,
          # instead we check the response
          get playground_prompt_path(id: 999999)
          expect(response).to have_http_status(:not_found)
        end
      end

      context "with prompt without parameters" do
        let(:simple_prompt) { create(:prompt, content: "Tell me a joke") }

        it "displays playground without parameter fields" do
          get playground_prompt_path(simple_prompt)
          expect(response).to be_successful
          expect(response.body).not_to include("Prompt Parameters")
        end
      end
    end

    describe "POST /prompt_engine/prompts/:id/playground" do
      let(:valid_params) do
        {
          api_key: "test-api-key",
          parameters: {
            topic: "Ruby on Rails",
            style: "technical"
          }
        }
      end

      before do
        # Mock RubyLLM to avoid actual API calls
        allow_any_instance_of(PlaygroundExecutor).to receive(:require).with("ruby_llm")

        # Mock the chat response
        chat_mock = instance_double(RUBY_LLM_CHAT_CLASS)
        response_mock = double("Response", content: "This is a test response about Ruby on Rails", input_tokens: 50, output_tokens: 100)

        stub_ruby_llm_context!(chat_double: chat_mock)
        allow(chat_mock).to receive(:with_temperature).and_return(chat_mock)
        allow(chat_mock).to receive(:with_instructions).and_return(chat_mock)
        allow(chat_mock).to receive(:ask).and_return(response_mock)
      end

      context "with valid parameters" do
        it "executes the prompt successfully" do
          post playground_prompt_path(prompt), params: valid_params

          expect(response).to be_successful
        end

        it "creates a PlaygroundRunResult record" do
          expect {
            post playground_prompt_path(prompt), params: valid_params
          }.to change(PlaygroundRunResult, :count).by(1)

          result = PlaygroundRunResult.last
          expect(result.prompt_version).to eq(prompt.current_version)
          expect(result.provider).to eq("openai")
          expect(result.model).to eq("gpt-4")
          expect(result.rendered_prompt).to eq("Tell me about Ruby on Rails in technical style")
          expect(result.response).to eq("This is a test response about Ruby on Rails")
          expect(result.execution_time).to be >= 0
          expect(result.token_count).to eq(150)
          expect(result.parameters).to eq({ "topic" => "Ruby on Rails", "style" => "technical" })
        end

        it "uses the model override without changing the saved prompt" do
          expect {
            post playground_prompt_path(prompt), params: valid_params.merge(model: "claude-3-opus-20240229")
          }.not_to change { prompt.reload.model }

          result = PlaygroundRunResult.last
          expect(result.model).to eq("claude-3-opus-20240229")
        end

        it "renders the result view" do
          post playground_prompt_path(prompt), params: valid_params

          expect(response.body).to include("Test Results")
          expect(response.body).to include("AI Response")
          expect(response.body).to include("This is a test response about Ruby on Rails")
        end

        it "displays execution metrics" do
          post playground_prompt_path(prompt), params: valid_params

          expect(response.body).to include("Execution Time")
          expect(response.body).to include("Tokens Used")
        end

        it "displays the rendered prompt" do
          post playground_prompt_path(prompt), params: valid_params

          expect(response.body).to include("Tell me about Ruby on Rails in technical style")
        end

        it "handles temperature settings from prompt" do
          prompt.update!(temperature: 0.5)

          post playground_prompt_path(prompt), params: valid_params
          expect(response).to be_successful
        end

        it "handles system message from prompt" do
          prompt.update!(system_message: "You are a technical writer")

          post playground_prompt_path(prompt), params: valid_params
          expect(response).to be_successful
        end
      end

      context "with an OpenAI model" do
        let(:openai_params) do
          {
            api_key: "test-openai-key",
            model: "gpt-4-turbo-preview",
            parameters: { topic: "Python", style: "casual" }
          }
        end

        it "executes with OpenAI successfully" do
          post playground_prompt_path(prompt), params: openai_params

          expect(response).to be_successful
          expect(response.body).to include("AI Response")
        end
      end

      context "with missing required parameters" do
        it "handles a prompt with no model selected" do
          modelless_prompt = create(:prompt, model: nil, content: "Tell me about {{topic}}")

          post playground_prompt_path(modelless_prompt), params: {
            api_key: "test-key",
            parameters: { topic: "Rails" }
          }

          expect(response).to be_successful
          expect(response.body).to include("Model is required")
        end

        it "handles missing API key when no Setting is stored" do
          post playground_prompt_path(prompt), params: {
            parameters: { topic: "Rails" }
          }

          expect(response).to be_successful
          expect(response.body).to include("API key is required")
        end

        it "handles a model with no known provider" do
          post playground_prompt_path(prompt), params: {
            api_key: "test-key",
            model: "mystery-model",
            parameters: { topic: "Rails" }
          }

          expect(response).to be_successful
          expect(response.body).to include("Unsupported model")
        end
      end

      context "resolving the API key server-side from Settings (CVP-1822)" do
        before do
          PromptEngine::Setting.instance.update!(openai_api_key: "sk-test-openai-key")
        end

        it "succeeds without an api_key param, using the saved Setting key" do
          post playground_prompt_path(prompt), params: {
            parameters: { topic: "Rails", style: "casual" }
          }

          expect(response).to be_successful
          expect(response.body).to include("AI Response")
        end

        it "treats a blank submitted api_key as 'use the saved key'" do
          post playground_prompt_path(prompt), params: {
            api_key: "",
            parameters: { topic: "Rails", style: "casual" }
          }

          expect(response).to be_successful
          expect(response.body).to include("AI Response")
        end

        it "coerces a non-String api_key (Array) to nil instead of erroring, and still uses the saved key" do
          post playground_prompt_path(prompt), params: {
            api_key: [ "x" ],
            parameters: { topic: "Rails", style: "casual" }
          }

          expect(response).to be_successful
          expect(response.body).to include("AI Response")
        end
      end

      context "with API errors" do
        it "handles unauthorized API key error" do
          allow_any_instance_of(PlaygroundExecutor).to receive(:execute).and_raise("Invalid API key")

          post playground_prompt_path(prompt), params: valid_params

          expect(response).to be_successful
          expect(response.body).to include("Invalid API key")
        end

        it "handles rate limit error" do
          allow_any_instance_of(PlaygroundExecutor).to receive(:execute).and_raise("Rate limit exceeded. Please try again later.")

          post playground_prompt_path(prompt), params: valid_params

          expect(response).to be_successful
          expect(response.body).to include("Rate limit exceeded")
        end

        it "handles network error" do
          allow_any_instance_of(PlaygroundExecutor).to receive(:execute).and_raise("Network error. Please check your connection and try again.")

          post playground_prompt_path(prompt), params: valid_params

          expect(response).to be_successful
          expect(response.body).to include("Network error")
        end

        it "handles generic errors" do
          allow_any_instance_of(PlaygroundExecutor).to receive(:execute).and_raise(StandardError, "Something went wrong")

          post playground_prompt_path(prompt), params: valid_params

          expect(response).to be_successful
          expect(response.body).to include("Something went wrong")
        end
      end

      context "with empty parameters" do
        it "handles nil parameters gracefully" do
          post playground_prompt_path(prompt), params: {
            api_key: "test-key",
            parameters: nil
          }

          expect(response).to be_successful
        end

        it "handles empty parameters hash" do
          post playground_prompt_path(prompt), params: {
            api_key: "test-key",
            parameters: {}
          }

          expect(response).to be_successful
        end
      end

      context "with prompt that has no parameters" do
        let(:simple_prompt) { create(:prompt, content: "Tell me a joke") }

        it "executes successfully without parameters" do
          post playground_prompt_path(simple_prompt), params: {
            api_key: "test-key"
          }

          expect(response).to be_successful
        end
      end

      context "when prompt does not exist" do
        it "raises ActiveRecord::RecordNotFound" do
          # In request specs, we check the response status
          post playground_prompt_path(id: 999999), params: valid_params
          expect(response).to have_http_status(:not_found)
        end
      end

      context "with different response structures" do
        it "handles string response" do
          chat_mock = instance_double(RUBY_LLM_CHAT_CLASS)
          stub_ruby_llm_context!(chat_double: chat_mock)
          allow(chat_mock).to receive(:with_temperature).and_return(chat_mock)
          allow(chat_mock).to receive(:with_instructions).and_return(chat_mock)
          allow(chat_mock).to receive(:ask).and_return("Simple string response")

          post playground_prompt_path(prompt), params: valid_params

          expect(response).to be_successful
          expect(response.body).to include("Simple string response")
        end

        it "handles object without content method" do
          chat_mock = instance_double(RUBY_LLM_CHAT_CLASS)
          response_obj = double("Response")
          allow(response_obj).to receive(:to_s).and_return("Object response")

          stub_ruby_llm_context!(chat_double: chat_mock)
          allow(chat_mock).to receive(:with_temperature).and_return(chat_mock)
          allow(chat_mock).to receive(:with_instructions).and_return(chat_mock)
          allow(chat_mock).to receive(:ask).and_return(response_obj)

          post playground_prompt_path(prompt), params: valid_params

          expect(response).to be_successful
          expect(response.body).to include("Object response")
        end
      end
    end
  end
end
