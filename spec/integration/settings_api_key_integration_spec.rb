require 'rails_helper'

RSpec.describe "Settings API Key Integration", type: :integration do
  let(:prompt) { create(:prompt) }
  let(:eval_set) { create(:eval_set, prompt: prompt) }
  let(:prompt_version) { create(:prompt_version, prompt: prompt) }
  let(:eval_run) { create(:eval_run, eval_set: eval_set, prompt_version: prompt_version) }

  describe "OpenAI client API key precedence" do
    context "when API key is set in Settings" do
      before do
        PromptEngine::Setting.instance.update!(openai_api_key: "sk-settings-key-123")
      end

      it "uses Settings API key over Rails credentials" do
        # Mock Rails credentials to return different key
        allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return("sk-rails-key-456")

        client = PromptEngine::OpenAiEvalsClient.new
        # The client should use the Settings key
        expect(client.instance_variable_get(:@api_key)).to eq("sk-settings-key-123")
      end

      it "passes Settings API key to evaluation runner" do
        runner = PromptEngine::EvaluationRunner.new(eval_run)
        client = runner.instance_variable_get(:@client)

        expect(client.instance_variable_get(:@api_key)).to eq("sk-settings-key-123")
      end
    end

    context "when API key is NOT set in Settings" do
      before do
        PromptEngine::Setting.instance.update!(openai_api_key: nil)
      end

      it "falls back to Rails credentials" do
        allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return("sk-rails-key-456")

        client = PromptEngine::OpenAiEvalsClient.new
        expect(client.instance_variable_get(:@api_key)).to eq("sk-rails-key-456")
      end
    end

    context "when no API key is available" do
      before do
        PromptEngine::Setting.instance.update!(openai_api_key: nil)
        allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return(nil)
      end

      it "raises authentication error" do
        expect {
          PromptEngine::OpenAiEvalsClient.new
        }.to raise_error(PromptEngine::OpenAiEvalsClient::AuthenticationError, "OpenAI API key not configured")
      end
    end
  end

  describe "Playground executor API key integration (CVP-1822)" do
    # Real PlaygroundExecutor constructor: prompt:, api_key: (optional), parameters:, model:.
    # No credentials fallback exists here (removed entirely) -- resolution is
    # explicit api_key override, then PromptEngine::Setting.first, and nothing else.
    def build_executor(model:)
      PromptEngine::PlaygroundExecutor.new(
        prompt: prompt,
        parameters: { topic: "test" },
        model: model
      )
    end

    context "with OpenAI model" do
      it "resolves the API key from Settings, applies it to a per-call RubyLLM context, and ignores Rails credentials" do
        PromptEngine::Setting.instance.update!(openai_api_key: "sk-settings-openai")
        allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return("sk-rails-openai")

        chat_double = instance_double(RubyLLM::Chat)
        ruby_llm = stub_ruby_llm_context!(chat_double: chat_double)
        allow(chat_double).to receive(:with_temperature).and_return(chat_double)
        allow(chat_double).to receive(:with_instructions).and_return(chat_double)
        allow(chat_double).to receive(:ask).and_return(double("Response", content: "Response"))

        executor = build_executor(model: "gpt-4")
        allow(executor).to receive(:require).with("ruby_llm")

        executor.execute

        expect(ruby_llm[:config]).to have_received(:openai_api_key=).with("sk-settings-openai")
        expect(Rails.application.credentials).not_to have_received(:dig).with(:openai, :api_key)
      end
    end

    context "with Anthropic model" do
      it "resolves the API key from Settings, applies it to a per-call RubyLLM context, and ignores Rails credentials" do
        PromptEngine::Setting.instance.update!(anthropic_api_key: "sk-ant-settings-key")
        allow(Rails.application.credentials).to receive(:dig).with(:anthropic, :api_key).and_return("sk-ant-rails-key")

        chat_double = instance_double(RubyLLM::Chat)
        ruby_llm = stub_ruby_llm_context!(chat_double: chat_double)
        allow(chat_double).to receive(:with_temperature).and_return(chat_double)
        allow(chat_double).to receive(:with_instructions).and_return(chat_double)
        allow(chat_double).to receive(:ask).and_return(double("Response", content: "Response"))

        executor = build_executor(model: "claude-3-sonnet")
        allow(executor).to receive(:require).with("ruby_llm")

        executor.execute

        expect(ruby_llm[:config]).to have_received(:anthropic_api_key=).with("sk-ant-settings-key")
        expect(Rails.application.credentials).not_to have_received(:dig).with(:anthropic, :api_key)
      end
    end

    it "does not raise when constructed without api_key: and leaves #api_key nil" do
      executor = PromptEngine::PlaygroundExecutor.new(prompt: prompt, parameters: { topic: "test" }, model: "gpt-4")

      expect(executor.api_key).to be_nil
    end
  end

  describe "Settings update workflow" do
    it "allows updating API keys through settings and immediately uses them" do
      # Start with no API key
      PromptEngine::Setting.instance.update!(openai_api_key: nil)

      # Verify client can't be created
      expect {
        PromptEngine::OpenAiEvalsClient.new
      }.to raise_error(PromptEngine::OpenAiEvalsClient::AuthenticationError)

      # Update settings with API key
      PromptEngine::Setting.instance.update!(openai_api_key: "sk-new-key-789")

      # Now client should work
      client = PromptEngine::OpenAiEvalsClient.new
      expect(client.instance_variable_get(:@api_key)).to eq("sk-new-key-789")
    end

    it "handles clearing API keys from settings" do
      # Start with API key in settings
      PromptEngine::Setting.instance.update!(openai_api_key: "sk-old-key")

      # Verify client works with key
      client = PromptEngine::OpenAiEvalsClient.new
      expect(client.instance_variable_get(:@api_key)).to eq("sk-old-key")

      # Clear settings API key to nil (not empty string)
      PromptEngine::Setting.instance.update!(openai_api_key: nil)

      # Set up Rails credentials as fallback
      allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return("sk-fallback-key")

      # Should fall back to Rails credentials
      client2 = PromptEngine::OpenAiEvalsClient.new
      expect(client2.instance_variable_get(:@api_key)).to eq("sk-fallback-key")
    end
  end

  describe "Error handling with invalid API keys" do
    before do
      PromptEngine::Setting.instance.update!(openai_api_key: "sk-invalid-key")
    end

    it "handles authentication errors gracefully in evaluation runner" do
      # Mock the client to simulate auth error
      mock_client = instance_double(PromptEngine::OpenAiEvalsClient)
      allow(PromptEngine::OpenAiEvalsClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:create_eval).and_raise(
        PromptEngine::OpenAiEvalsClient::AuthenticationError, "Invalid API key"
      )

      runner = PromptEngine::EvaluationRunner.new(eval_run)

      expect { runner.execute }.to raise_error(PromptEngine::OpenAiEvalsClient::AuthenticationError)

      eval_run.reload
      expect(eval_run.status).to eq("failed")
      expect(eval_run.error_message).to eq("Invalid API key")
    end
  end

  describe "Multiple provider API keys" do
    it "manages separate API keys for different providers" do
      # Set different keys for different providers
      PromptEngine::Setting.instance.update!(
        openai_api_key: "sk-openai-123",
        anthropic_api_key: "sk-ant-456"
      )

      # Verify OpenAI client uses OpenAI key
      openai_client = PromptEngine::OpenAiEvalsClient.new
      expect(openai_client.instance_variable_get(:@api_key)).to eq("sk-openai-123")

      # Verify Anthropic operations would use Anthropic key
      settings = PromptEngine::Setting.instance
      expect(settings.openai_api_key).to eq("sk-openai-123")
      expect(settings.anthropic_api_key).to eq("sk-ant-456")
    end
  end
end
