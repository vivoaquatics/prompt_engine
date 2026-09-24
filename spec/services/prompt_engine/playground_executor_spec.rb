require "rails_helper"

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

    it "does not raise when api_key is omitted, and leaves api_key nil" do
      executor = described_class.new(prompt: prompt)

      expect(executor.api_key).to be_nil
    end

    it "coerces a non-String api_key (Array) to nil rather than passing it through" do
      executor = described_class.new(prompt: prompt, api_key: [ "x" ])

      expect(executor.api_key).to be_nil
    end

    it "coerces a non-String api_key (Hash) to nil rather than passing it through" do
      executor = described_class.new(prompt: prompt, api_key: { "foo" => "bar" })

      expect(executor.api_key).to be_nil
    end

    it "coerces a non-String api_key (Integer) to nil rather than passing it through" do
      executor = described_class.new(prompt: prompt, api_key: 12345)

      expect(executor.api_key).to be_nil
    end

    it "excludes key material from #instance_variables" do
      executor = described_class.new(prompt: prompt, api_key: "super-secret-key")

      expect(executor.instance_variables).not_to include(:@api_key)
      expect(executor.instance_variables).not_to include(:@resolved_api_key)
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
      # Mock the require to prevent loading the actual gem a second time.
      allow(executor).to receive(:require).with("ruby_llm")
    end

    context "with successful API call" do
      let(:mock_chat) { instance_double(RubyLLM::Chat) }
      let(:mock_response) { double("response", content: "Here's information about ruby programming in casual style") }

      before do
        stub_ruby_llm_context!(chat_double: mock_chat)
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

      let(:mock_chat) { instance_double(RubyLLM::Chat) }
      let(:mock_response) { double("response", content: "Claude response") }

      before do
        allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response)
      end

      it "applies the Anthropic API key to the per-call context, not global config" do
        ruby_llm = stub_ruby_llm_context!(chat_double: mock_chat)

        executor.execute

        expect(ruby_llm[:config]).to have_received(:anthropic_api_key=).with("anthropic-key")
        expect(ruby_llm[:config]).not_to have_received(:openai_api_key=)
        expect(ruby_llm[:global_config]).not_to have_received(:anthropic_api_key=)
        expect(ruby_llm[:global_config]).not_to have_received(:openai_api_key=)
      end

      it "never calls RubyLLM.configure (the process-wide, non-scoped API)" do
        ruby_llm = stub_ruby_llm_context!(chat_double: mock_chat)
        # :configure is deliberately left unstubbed on this verifying double:
        # if the executor called it, RSpec would raise "received unexpected
        # message" and fail this example loudly.

        executor.execute

        expect(ruby_llm[:module]).to have_received(:context)
      end

      it "uses the selected model" do
        stub_ruby_llm_context!(chat_double: mock_chat)

        result = executor.execute

        expect(result[:model]).to eq("claude-3-5-sonnet-20241022")
        expect(result[:provider]).to eq("anthropic")
      end

      it "uses a model override without changing the prompt's saved model" do
        stub_ruby_llm_context!(chat_double: mock_chat)

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
        stub_ruby_llm_context!(chat_double: mock_chat)

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

      it "raises error when API key is blank and no Setting is stored" do
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

      it "raises for a provider outside SETTINGS_KEY_PROVIDERS before ever touching RubyLLM" do
        original = PromptEngine.configuration.model_provider_patterns
        PromptEngine.configuration.model_provider_patterns =
          original.merge("cohere" => /\Acommand-/i)

        class_double(RubyLLM).as_stubbed_const
        # Intentionally leave `.context` unstubbed: it must never be called.

        executor = described_class.new(
          prompt: prompt,
          api_key: "explicit-key",
          parameters: valid_parameters,
          model: "command-r-plus"
        )

        expect { executor.execute }.to raise_error(ArgumentError, "Unsupported provider: cohere")
        # :context is deliberately left unstubbed above: if llm_context were
        # ever reached, RSpec would raise "received unexpected message" and
        # fail this example loudly rather than silently succeeding.
      ensure
        PromptEngine.configuration.model_provider_patterns = original
      end
    end

    context "API key resolution precedence (CVP-1822)" do
      let(:mock_chat) { instance_double(RubyLLM::Chat) }
      let(:mock_response) { double("response", content: "response") }

      def stub_successful_chat!
        ruby_llm = stub_ruby_llm_context!(chat_double: mock_chat)
        allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_response)
        ruby_llm
      end

      it "resolves the key from Setting when no explicit key is submitted" do
        PromptEngine::Setting.first_or_create!.update!(openai_api_key: "sk-test-openai-key")
        ruby_llm = stub_successful_chat!

        executor = described_class.new(prompt: prompt, parameters: valid_parameters)
        allow(executor).to receive(:require).with("ruby_llm")

        result = executor.execute

        expect(result[:provider]).to eq("openai")
        expect(ruby_llm[:config]).to have_received(:openai_api_key=).with("sk-test-openai-key")
      end

      it "prefers an explicit override over a stored Setting key" do
        PromptEngine::Setting.first_or_create!.update!(openai_api_key: "sk-test-openai-key")
        ruby_llm = stub_successful_chat!

        executor = described_class.new(prompt: prompt, api_key: "explicit-override", parameters: valid_parameters)
        allow(executor).to receive(:require).with("ruby_llm")

        executor.execute

        expect(ruby_llm[:config]).to have_received(:openai_api_key=).with("explicit-override")
      end

      it "does not bleed the openai key into an anthropic request" do
        PromptEngine::Setting.first_or_create!.update!(openai_api_key: "sk-test-openai-key")

        executor = described_class.new(
          prompt: prompt,
          parameters: valid_parameters,
          model: "claude-3-opus"
        )
        allow(executor).to receive(:require).with("ruby_llm")

        expect { executor.execute }.to raise_error(ArgumentError, "API key is required")
      end

      it "raises when neither Setting nor an explicit key is present" do
        executor = described_class.new(prompt: prompt, parameters: valid_parameters)
        allow(executor).to receive(:require).with("ruby_llm")

        expect { executor.execute }.to raise_error(ArgumentError, "API key is required")
      end

      it "never falls back to Rails.application.credentials (fallback removed, CVP-1822)" do
        allow(Rails.application.credentials).to receive(:dig).and_call_original
        # A sentinel value that would satisfy resolution if credentials were
        # (wrongly) consulted. It must never be read.
        allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return("sentinel-from-credentials")

        executor = described_class.new(prompt: prompt, parameters: valid_parameters)
        allow(executor).to receive(:require).with("ruby_llm")

        expect { executor.execute }.to raise_error(ArgumentError, "API key is required")
        expect(Rails.application.credentials).not_to have_received(:dig).with(:openai, :api_key)
      end

      it "does not define a private credentials_api_key method (fallback removed entirely)" do
        executor = described_class.new(prompt: prompt, parameters: valid_parameters)

        expect(executor.respond_to?(:credentials_api_key, true)).to be(false)
      end

      it "does not create a Setting row as a side effect of key resolution (Setting.first, not .instance)" do
        expect(PromptEngine::Setting.count).to eq(0)

        executor = described_class.new(prompt: prompt, parameters: valid_parameters)
        allow(executor).to receive(:require).with("ruby_llm")

        expect { executor.execute }.to raise_error(ArgumentError, "API key is required")
        expect(PromptEngine::Setting.count).to eq(0)
      end
    end
  end

  describe "#execute global RubyLLM.config isolation" do
    it "never mutates RubyLLM.config -- the key is scoped to the per-call context only" do
      ruby_llm = stub_ruby_llm_context!
      chat_double = ruby_llm[:chat]
      allow(chat_double).to receive(:with_temperature).and_return(chat_double)
      allow(chat_double).to receive(:with_instructions).and_return(chat_double)
      allow(chat_double).to receive(:ask).and_return(double("response", content: "ok"))

      executor = described_class.new(prompt: prompt, api_key: "explicit-override", parameters: valid_parameters)
      allow(executor).to receive(:require).with("ruby_llm")

      executor.execute

      expect(ruby_llm[:global_config]).not_to have_received(:openai_api_key=)
      expect(ruby_llm[:global_config]).not_to have_received(:anthropic_api_key=)
      expect(ruby_llm[:context]).to have_received(:chat).with(model: "gpt-4o")
    end
  end

  describe "with API errors" do
    let(:executor) do
      described_class.new(
        prompt: prompt,
        api_key: "test-api-key",
        parameters: valid_parameters
      )
    end

    let(:mock_chat) { instance_double(RubyLLM::Chat) }

    before do
      allow(executor).to receive(:require).with("ruby_llm")
      stub_ruby_llm_context!(chat_double: mock_chat)
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

  describe "with prompt without optional fields" do
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

    let(:mock_chat) { instance_double(RubyLLM::Chat) }
    let(:mock_response) { double("response", content: "Response") }

    before do
      allow(executor).to receive(:require).with("ruby_llm")
      stub_ruby_llm_context!(chat_double: mock_chat)
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
