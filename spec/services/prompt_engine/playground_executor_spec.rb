require 'rails_helper'

RSpec.describe PromptEngine::PlaygroundExecutor, type: :service do
  let(:prompt) do
    FactoryBot.create(:prompt,
      content: "Tell me about {{topic}} in {{style}} style",
      system_message: "You are a helpful assistant",
      model: "gpt-4o",
      temperature: 0.8,
      max_tokens: 150
    )
  end

  let(:valid_parameters) do
    {
      topic: "ruby programming",
      style: "casual"
    }
  end

  describe "#initialize" do
    it "initializes with required attributes" do
      executor = described_class.new(
        prompt: prompt,
        api_key: "test-key",
        parameters: valid_parameters
      )

      expect(executor.prompt).to eq(prompt)
      expect(executor.api_key).to eq("test-key")
      expect(executor.parameters).to eq(valid_parameters)
    end

    it "infers the provider from the selected model" do
      executor = described_class.new(
        prompt: prompt,
        api_key: "test-key",
        model: "claude-3-opus"
      )

      expect(executor.provider).to eq("anthropic")
    end

    it "initializes with nil parameters as empty hash" do
      executor = described_class.new(
        prompt: prompt,
        api_key: "test-key",
        parameters: nil
      )

      expect(executor.parameters).to eq({})
    end
  end

  describe "#execute" do
    let(:executor) do
      described_class.new(
        prompt: prompt,
        api_key: "test-api-key",
        parameters: valid_parameters
      )
    end

    before do
      # Mock the require to prevent loading the actual gem
      allow(executor).to receive(:require).with('ruby_llm')

      # Create a config double outside the module
      config = double('Config')
      allow(config).to receive(:anthropic_api_key=)
      allow(config).to receive(:openai_api_key=)

      # Create a mock RubyLLM module
      mock_ruby_llm = Module.new
      mock_ruby_llm.define_singleton_method(:configure) do |&block|
        block.call(config)
      end
      mock_ruby_llm.define_singleton_method(:chat) do |options = {}|
        # This will be overridden in specific tests
      end

      stub_const("RubyLLM", mock_ruby_llm)
    end

    context "with successful API call" do
      let(:mock_chat) { double("chat") }
      let(:mock_response) { double("response", content: "Here's information about ruby programming in casual style") }

      before do
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response)
      end

      it "returns successful response with content" do
        result = executor.execute

        expect(result[:response]).to eq("Here's information about ruby programming in casual style")
        expect(result[:model]).to eq("gpt-4o")
        expect(result[:provider]).to eq("openai")
        expect(result[:execution_time]).to be_a(Float)
        expect(result[:token_count]).to eq(0)
      end

      it "applies temperature when specified" do
        expect(mock_chat).to receive(:with_temperature).with(0.8).and_return(mock_chat)

        executor.execute
      end

      it "applies system message when present" do
        expect(mock_chat).to receive(:with_instructions).with("You are a helpful assistant").and_return(mock_chat)

        executor.execute
      end

      it "replaces parameters in prompt content" do
        expect(mock_chat).to receive(:ask).with("Tell me about ruby programming in casual style")

        executor.execute
      end

      context "with response containing token information" do
        let(:mock_response) do
          double("response",
            content: "Response content",
            input_tokens: 50,
            output_tokens: 100
          )
        end

        it "calculates total token count" do
          result = executor.execute

          expect(result[:token_count]).to eq(150)
        end
      end

      context "with string response" do
        let(:mock_response) { "Simple string response" }

        it "handles string response correctly" do
          result = executor.execute

          expect(result[:response]).to eq("Simple string response")
        end
      end
    end

    context "with Anthropic provider" do
      let(:executor) do
        described_class.new(
          prompt: prompt,
          api_key: "anthropic-key",
          parameters: valid_parameters,
          model: "claude-3-5-sonnet-20241022"
        )
      end

      let(:mock_chat) { double("chat") }
      let(:mock_response) { double("response", content: "Claude response") }

      before do
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response)
      end

      it "configures Anthropic API key" do
        config_set = false
        allow(RubyLLM).to receive(:configure) do |&block|
          config = double('Config')
          expect(config).to receive(:anthropic_api_key=).with("anthropic-key")
          allow(config).to receive(:openai_api_key=)
          block.call(config)
          config_set = true
        end

        executor.execute
        expect(config_set).to be true
      end

      it "uses the selected model" do
        result = executor.execute

        expect(result[:model]).to eq("claude-3-5-sonnet-20241022")
        expect(result[:provider]).to eq("anthropic")
      end

      it "uses a model override without changing the prompt's saved model" do
        override_executor = described_class.new(
          prompt: prompt,
          api_key: "anthropic-key",
          parameters: valid_parameters,
          model: "claude-3-opus-20240229"
        )
        allow(override_executor).to receive(:require).with("ruby_llm")

        result = override_executor.execute

        expect(result[:model]).to eq("claude-3-opus-20240229")
        expect(result[:provider]).to eq("anthropic")
        expect(prompt.model).to eq("gpt-4o")
      end

      it "falls back to the prompt's saved model when no override is given" do
        fallback_executor = described_class.new(
          prompt: prompt,
          api_key: "anthropic-key",
          parameters: valid_parameters
        )
        allow(fallback_executor).to receive(:require).with("ruby_llm")

        result = fallback_executor.execute

        expect(result[:model]).to eq("gpt-4o")
        expect(result[:provider]).to eq("openai")
      end
    end

    context "with validation errors" do
      it "raises error when no model is selected" do
        prompt_without_model = FactoryBot.create(:prompt, model: nil)
        executor = described_class.new(
          prompt: prompt_without_model,
          api_key: "test-key",
          parameters: valid_parameters
        )

        expect { executor.execute }.to raise_error(ArgumentError, "Model is required")
      end

      it "raises error when API key is blank" do
        executor = described_class.new(
          prompt: prompt,
          api_key: "",
          parameters: valid_parameters
        )

        expect { executor.execute }.to raise_error(ArgumentError, "API key is required")
      end

      it "raises error for a model that maps to no known provider" do
        executor = described_class.new(
          prompt: prompt,
          api_key: "test-key",
          parameters: valid_parameters,
          model: "some-unknown-model"
        )

        expect { executor.execute }.to raise_error(ArgumentError, "Unsupported model: some-unknown-model")
      end
    end

    context "with API errors" do
      let(:mock_chat) { double("chat") }

      before do
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
      end

      it "handles unauthorized errors" do
        # The implementation checks for Net::HTTPUnauthorized class
        stub_const("Net::HTTPUnauthorized", Class.new(StandardError))
        unauthorized_error = Net::HTTPUnauthorized.new("Unauthorized")
        allow(mock_chat).to receive(:ask).and_raise(unauthorized_error)

        expect { executor.execute }.to raise_error(RuntimeError, "Invalid API key")
      end

      it "handles rate limit errors" do
        # The implementation checks for Net::HTTPTooManyRequests class
        stub_const("Net::HTTPTooManyRequests", Class.new(StandardError))
        rate_limit_error = Net::HTTPTooManyRequests.new("Too Many Requests")
        allow(mock_chat).to receive(:ask).and_raise(rate_limit_error)

        expect { executor.execute }.to raise_error(RuntimeError, "Rate limit exceeded. Please try again later.")
      end

      it "handles network errors" do
        # The implementation checks for Net::HTTPError class
        stub_const("Net::HTTPError", Class.new(StandardError))
        network_error = Net::HTTPError.new("Network error")
        allow(mock_chat).to receive(:ask).and_raise(network_error)

        expect { executor.execute }.to raise_error(RuntimeError, "Network error. Please check your connection and try again.")
      end

      it "handles generic errors" do
        allow(mock_chat).to receive(:ask).and_raise(StandardError.new("Something went wrong"))

        expect { executor.execute }.to raise_error(RuntimeError, "An error occurred: Something went wrong")
      end

      it "handles errors with unauthorized message" do
        allow(mock_chat).to receive(:ask).and_raise(StandardError.new("Request unauthorized"))

        expect { executor.execute }.to raise_error(RuntimeError, "Invalid API key")
      end

      it "handles errors with rate limit message" do
        allow(mock_chat).to receive(:ask).and_raise(StandardError.new("Rate limit exceeded"))

        expect { executor.execute }.to raise_error(RuntimeError, "Rate limit exceeded. Please try again later.")
      end
    end

    context "with prompt without optional fields" do
      let(:minimal_prompt) do
        FactoryBot.create(:prompt,
          content: "Simple prompt",
          system_message: nil,
          model: "gpt-4o",
          temperature: nil
        )
      end

      let(:executor) do
        described_class.new(
          prompt: minimal_prompt,
          api_key: "test-key",
          parameters: {}
        )
      end

      let(:mock_chat) { double("chat") }
      let(:mock_response) { double("response", content: "Response") }

      before do
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response)
      end

      it "does not apply temperature when not present" do
        expect(mock_chat).not_to receive(:with_temperature)

        executor.execute
      end

      it "does not apply system message when not present" do
        expect(mock_chat).not_to receive(:with_instructions)

        executor.execute
      end
    end
  end

  describe "#provider" do
    def provider_for(model)
      described_class.new(prompt: prompt, api_key: "test-key", model: model).provider
    end

    it "infers anthropic from Claude model ids" do
      expect(provider_for("claude-3-opus")).to eq("anthropic")
    end

    it "infers openai from GPT model ids" do
      expect(provider_for("gpt-4-turbo-preview")).to eq("openai")
    end

    it "returns nil for models it cannot map" do
      expect(provider_for("some-unknown-model")).to be_nil
    end

    it "honors custom configured patterns" do
      original = PromptEngine.configuration.model_provider_patterns
      PromptEngine.configuration.model_provider_patterns =
        original.merge("openai" => /\A(gpt|my-llm)/i)

      expect(provider_for("my-llm-7b")).to eq("openai")
    ensure
      PromptEngine.configuration.model_provider_patterns = original
    end
  end

  describe "#selected_model" do
    it "returns the override when one is provided" do
      executor = described_class.new(
        prompt: prompt,
        api_key: "test-key",
        model: "gpt-4-turbo-preview"
      )

      expect(executor.selected_model).to eq("gpt-4-turbo-preview")
    end

    it "falls back to the prompt's saved model when no override is given" do
      executor = described_class.new(
        prompt: prompt,
        api_key: "test-key"
      )

      expect(executor.selected_model).to eq(prompt.model)
    end
  end
end
