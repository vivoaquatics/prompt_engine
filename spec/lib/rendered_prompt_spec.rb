require "rails_helper"

module PromptEngine
  RSpec.describe RenderedPrompt do
    let(:prompt) do
      create(:prompt,
        slug: "test-prompt",
        content: "Hello {{name}}",
        system_message: "You are a helpful assistant",
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000,
        status: "active"
      )
    end

    let(:rendered_data) do
      {
        content: "Hello Alice",
        system_message: "You are a helpful assistant",
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000,
        parameters_used: { "name" => "Alice" },
        version_number: 1
      }
    end

    let(:overrides) do
      {
        model: "gpt-4-turbo",
        temperature: 0.9,
        status: "draft"
      }
    end

    let(:rendered_prompt) { described_class.new(prompt, rendered_data, overrides) }

    describe "#options" do
      it "returns a copy of the overrides hash" do
        expect(rendered_prompt.options).to eq(overrides)
        expect(rendered_prompt.options).not_to be(overrides) # Should be a copy
      end

      it "returns empty hash when no overrides provided" do
        prompt_without_overrides = described_class.new(prompt, rendered_data)
        expect(prompt_without_overrides.options).to eq({})
      end
    end

    describe "#status" do
      it "returns the status from overrides if provided" do
        expect(rendered_prompt.status).to eq("draft")
      end

      it "returns the prompt's status if not overridden" do
        prompt_without_status = described_class.new(prompt, rendered_data, { model: "gpt-4" })
        expect(prompt_without_status.status).to eq("active")
      end
    end

    describe "#version" do
      it "returns the version number from rendered data" do
        expect(rendered_prompt.version).to eq(1)
      end

      it "returns nil if no version number" do
        data_without_version = rendered_data.except(:version_number)
        prompt_no_version = described_class.new(prompt, data_without_version)
        expect(prompt_no_version.version).to be_nil
      end
    end

    describe "#model" do
      it "returns overridden model when provided" do
        expect(rendered_prompt.model).to eq("gpt-4-turbo")
      end

      it "returns rendered data model when not overridden" do
        prompt_no_override = described_class.new(prompt, rendered_data, {})
        expect(prompt_no_override.model).to eq("gpt-4")
      end
    end

    describe "#temperature" do
      it "returns overridden temperature when provided" do
        expect(rendered_prompt.temperature).to eq(0.9)
      end

      it "returns rendered data temperature when not overridden" do
        prompt_no_override = described_class.new(prompt, rendered_data, {})
        expect(prompt_no_override.temperature).to eq(0.7)
      end
    end

    describe "#max_tokens" do
      it "returns overridden max_tokens when provided" do
        with_max_tokens = described_class.new(prompt, rendered_data, { max_tokens: 2000 })
        expect(with_max_tokens.max_tokens).to eq(2000)
      end

      it "returns rendered data max_tokens when not overridden" do
        expect(rendered_prompt.max_tokens).to eq(1000)
      end
    end

    describe "#reasoning_effort" do
      it "returns nil for a model that supports no reasoning" do
        data = rendered_data.merge(model: "gpt-4", reasoning_effort: nil)
        prompt_no_reasoning = described_class.new(prompt, data, {})

        expect(prompt_no_reasoning.reasoning_effort).to be_nil
      end

      it "defaults to low at request time when the model supports reasoning but nothing is stored" do
        data = rendered_data.merge(model: "gpt-5.6-sol", reasoning_effort: nil)
        prompt_with_reasoning = described_class.new(prompt, data, {})

        expect(prompt_with_reasoning.reasoning_effort).to eq("low")
      end

      it "passes through a stored value that is valid for the model" do
        data = rendered_data.merge(model: "gpt-5.6-sol", reasoning_effort: "xhigh")
        prompt_with_reasoning = described_class.new(prompt, data, {})

        expect(prompt_with_reasoning.reasoning_effort).to eq("xhigh")
      end

      it "prefers an override over the stored value" do
        data = rendered_data.merge(model: "gpt-5.6-sol", reasoning_effort: "low")
        prompt_with_override = described_class.new(prompt, data, { reasoning_effort: "max" })

        expect(prompt_with_override.reasoning_effort).to eq("max")
      end

      it "resolves against an overridden model, not the rendered data's model" do
        data = rendered_data.merge(model: "gpt-4", reasoning_effort: nil)
        prompt_with_model_override = described_class.new(prompt, data, { model: "gpt-5.6-sol" })

        expect(prompt_with_model_override.reasoning_effort).to eq("low")
      end

      it "returns nil for a budget-mode Anthropic model - that value is a token count, not this string" do
        data = rendered_data.merge(model: "claude-haiku-4-5", reasoning_effort: "medium")
        prompt_budget_mode = described_class.new(prompt, data, {})

        expect(prompt_budget_mode.reasoning_effort).to be_nil
      end
    end

    describe "#reasoning_thinking_args" do
      it "returns an effort hash for an effort-mode Anthropic model" do
        data = rendered_data.merge(model: "claude-opus-4-8", reasoning_effort: "xhigh")
        rp = described_class.new(prompt, data, {})

        expect(rp.reasoning_thinking_args).to eq({ effort: "xhigh" })
      end

      it "returns a budget hash (token count) for a budget-mode Anthropic model" do
        data = rendered_data.merge(model: "claude-haiku-4-5", reasoning_effort: "medium")
        rp = described_class.new(prompt, data, {})

        expect(rp.reasoning_thinking_args).to eq({ budget: 8192 })
      end

      it "returns nil for a non-reasoning model" do
        data = rendered_data.merge(model: "gpt-4", reasoning_effort: nil)
        rp = described_class.new(prompt, data, {})

        expect(rp.reasoning_thinking_args).to be_nil
      end
    end

    describe "#system_message" do
      it "returns overridden system_message when provided" do
        with_system = described_class.new(prompt, rendered_data, { system_message: "New system message" })
        expect(with_system.system_message).to eq("New system message")
      end

      it "returns rendered data system_message when not overridden" do
        expect(rendered_prompt.system_message).to eq("You are a helpful assistant")
      end
    end

    describe "#to_h" do
      it "includes all the expected keys" do
        hash = rendered_prompt.to_h
        expect(hash).to include(
          content: "Hello Alice",
          system_message: "You are a helpful assistant",
          model: "gpt-4-turbo",
          temperature: 0.9,
          max_tokens: 1000,
          status: "draft",
          version: 1,
          options: overrides,
          parameters: { "name" => "Alice" }
        )
      end

      it "never includes reasoning_effort, for effort-mode or budget-mode Anthropic families" do
        effort_data = rendered_data.merge(model: "claude-opus-4-8", reasoning_effort: "high")
        budget_data = rendered_data.merge(model: "claude-haiku-4-5", reasoning_effort: "medium")

        expect(described_class.new(prompt, effort_data).to_h).not_to have_key(:reasoning_effort)
        expect(described_class.new(prompt, budget_data).to_h).not_to have_key(:reasoning_effort)
      end
    end

    describe "backward compatibility" do
      it "still exposes content as attr_reader" do
        expect(rendered_prompt.content).to eq("Hello Alice")
      end

      it "still exposes overrides as attr_reader" do
        expect(rendered_prompt.overrides).to eq(overrides)
      end

      it "still exposes version_number as attr_reader" do
        expect(rendered_prompt.version_number).to eq(1)
      end
    end

    describe "#messages" do
      context "with system message" do
        let(:rendered_data) do
          {
            content: "Hello world",
            system_message: "You are a helpful assistant",
            model: "gpt-4",
            temperature: 0.7,
            max_tokens: 1000,
            parameters_used: {},
            version_number: 1
          }
        end

        it "returns array with system and user messages in correct order" do
          prompt_with_system = described_class.new(prompt, rendered_data)
          messages = prompt_with_system.messages

          expect(messages).to eq([
            { role: "system", content: "You are a helpful assistant" },
            { role: "user", content: "Hello world" }
          ])
        end

        it "uses system message from overrides when provided" do
          overrides_with_system = { system_message: "Override system message" }
          prompt_with_override = described_class.new(prompt, rendered_data, overrides_with_system)
          messages = prompt_with_override.messages

          expect(messages).to eq([
            { role: "system", content: "Override system message" },
            { role: "user", content: "Hello world" }
          ])
        end
      end

      context "without system message" do
        let(:rendered_data_no_system) do
          {
            content: "Hello world",
            system_message: nil,
            model: "gpt-4",
            temperature: 0.7,
            max_tokens: 1000,
            parameters_used: {},
            version_number: 1
          }
        end

        it "returns array with only user message when system_message is nil" do
          prompt_no_system = described_class.new(prompt, rendered_data_no_system)
          messages = prompt_no_system.messages

          expect(messages).to eq([
            { role: "user", content: "Hello world" }
          ])
        end

        it "returns array with only user message when system_message is empty string" do
          data_empty_system = rendered_data_no_system.merge(system_message: "")
          prompt_empty_system = described_class.new(prompt, data_empty_system)
          messages = prompt_empty_system.messages

          expect(messages).to eq([
            { role: "user", content: "Hello world" }
          ])
        end

        it "returns array with only user message when system_message is whitespace" do
          data_whitespace_system = rendered_data_no_system.merge(system_message: "   ")
          prompt_whitespace_system = described_class.new(prompt, data_whitespace_system)
          messages = prompt_whitespace_system.messages

          expect(messages).to eq([
            { role: "user", content: "Hello world" }
          ])
        end
      end

      context "with different content" do
        it "always includes the content as user message" do
          data_with_content = rendered_data.merge(content: "Complex prompt with {{variables}}")
          prompt_complex = described_class.new(prompt, data_with_content)
          messages = prompt_complex.messages

          expect(messages.last).to eq({ role: "user", content: "Complex prompt with {{variables}}" })
        end
      end
    end

    describe "#to_openai_params" do
      context "with all parameters provided" do
        let(:rendered_data) do
          {
            content: "Test prompt",
            system_message: "You are helpful",
            model: "gpt-4",
            temperature: 0.7,
            max_tokens: 1000,
            parameters_used: {},
            version_number: 1
          }
        end

        it "returns OpenAI-formatted parameters with all fields" do
          prompt_full = described_class.new(prompt, rendered_data)
          params = prompt_full.to_openai_params

          expect(params).to eq({
            model: "gpt-4",
            messages: [
              { role: "system", content: "You are helpful" },
              { role: "user", content: "Test prompt" }
            ],
            temperature: 0.7,
            max_tokens: 1000
          })
        end

        it "uses the messages method to build messages array" do
          prompt_test = described_class.new(prompt, rendered_data)
          expect(prompt_test).to receive(:messages).and_call_original
          prompt_test.to_openai_params
        end
      end

      context "with nil model" do
        let(:rendered_data_no_model) do
          {
            content: "Test prompt",
            system_message: "System",
            model: nil,
            temperature: 0.5,
            max_tokens: 500,
            parameters_used: {},
            version_number: 1
          }
        end

        it "defaults to gpt-4 when model is nil" do
          prompt_no_model = described_class.new(prompt, rendered_data_no_model)
          params = prompt_no_model.to_openai_params

          expect(params[:model]).to eq("gpt-4")
        end
      end

      context "with nil values" do
        let(:rendered_data_with_nils) do
          {
            content: "Test prompt",
            system_message: nil,
            model: "gpt-3.5-turbo",
            temperature: nil,
            max_tokens: nil,
            parameters_used: {},
            version_number: 1
          }
        end

        it "removes nil values with compact" do
          prompt_with_nils = described_class.new(prompt, rendered_data_with_nils)
          params = prompt_with_nils.to_openai_params

          expect(params).to eq({
            model: "gpt-3.5-turbo",
            messages: [
              { role: "user", content: "Test prompt" }
            ]
          })
          expect(params).not_to have_key(:temperature)
          expect(params).not_to have_key(:max_tokens)
        end
      end

      context "with additional options" do
        it "merges additional options into the parameters" do
          prompt_test = described_class.new(prompt, rendered_data)
          params = prompt_test.to_openai_params(
            tools: [ { type: "function", function: { name: "test" } } ],
            stream: true,
            response_format: { type: "json_object" }
          )

          expect(params).to include(
            model: "gpt-4",
            messages: anything,
            temperature: 0.7,
            max_tokens: 1000,
            tools: [ { type: "function", function: { name: "test" } } ],
            stream: true,
            response_format: { type: "json_object" }
          )
        end

        it "allows additional options to override base parameters" do
          prompt_test = described_class.new(prompt, rendered_data)
          params = prompt_test.to_openai_params(
            model: "gpt-4-turbo",
            temperature: 0.9
          )

          expect(params[:model]).to eq("gpt-4-turbo")
          expect(params[:temperature]).to eq(0.9)
        end
      end

      context "with overrides from constructor" do
        let(:test_rendered_data) do
          {
            content: "Test prompt",
            system_message: "Original system",
            model: "gpt-4",
            temperature: 0.7,
            max_tokens: 1000,
            parameters_used: {},
            version_number: 1
          }
        end

        let(:test_overrides) do
          {
            model: "gpt-4-turbo",
            temperature: 0.3,
            max_tokens: 2000,
            system_message: "Override system"
          }
        end

        it "uses override values in the output" do
          prompt_with_overrides = described_class.new(prompt, test_rendered_data, test_overrides)
          params = prompt_with_overrides.to_openai_params

          expect(params).to eq({
            model: "gpt-4-turbo",
            messages: [
              { role: "system", content: "Override system" },
              { role: "user", content: "Test prompt" }
            ],
            temperature: 0.3,
            max_tokens: 2000
          })
        end
      end

      context "with a reasoning-capable OpenAI model" do
        let(:reasoning_rendered_data) do
          {
            content: "Test prompt",
            system_message: "You are helpful",
            model: "gpt-5.6-sol",
            temperature: 0.7,
            max_tokens: 1000,
            reasoning_effort: "xhigh",
            parameters_used: {},
            version_number: 1
          }
        end

        it "includes reasoning_effort as a genuine OpenAI wire parameter" do
          prompt_reasoning = described_class.new(prompt, reasoning_rendered_data)

          expect(prompt_reasoning.to_openai_params[:reasoning_effort]).to eq("xhigh")
        end
      end
    end

    describe "#to_ruby_llm_params" do
      context "with all parameters provided" do
        let(:rendered_data) do
          {
            content: "Test prompt",
            system_message: "You are helpful",
            model: "claude-3-opus",
            temperature: 0.7,
            max_tokens: 1000,
            parameters_used: {},
            version_number: 1
          }
        end

        it "returns RubyLLM-formatted parameters with all fields" do
          prompt_full = described_class.new(prompt, rendered_data)
          params = prompt_full.to_ruby_llm_params

          expect(params).to eq({
            messages: [
              { role: "system", content: "You are helpful" },
              { role: "user", content: "Test prompt" }
            ],
            model: "claude-3-opus",
            temperature: 0.7,
            max_tokens: 1000
          })
        end

        it "has messages as the first key in the hash" do
          prompt_test = described_class.new(prompt, rendered_data)
          params = prompt_test.to_ruby_llm_params

          expect(params.keys.first).to eq(:messages)
        end

        it "uses the messages method to build messages array" do
          prompt_test = described_class.new(prompt, rendered_data)
          expect(prompt_test).to receive(:messages).and_call_original
          prompt_test.to_ruby_llm_params
        end
      end

      context "with nil model" do
        let(:rendered_data_no_model) do
          {
            content: "Test prompt",
            system_message: "System",
            model: nil,
            temperature: 0.5,
            max_tokens: 500,
            parameters_used: {},
            version_number: 1
          }
        end

        it "defaults to gpt-4 when model is nil" do
          prompt_no_model = described_class.new(prompt, rendered_data_no_model)
          params = prompt_no_model.to_ruby_llm_params

          expect(params[:model]).to eq("gpt-4")
        end
      end

      context "with nil values" do
        let(:rendered_data_with_nils) do
          {
            content: "Test prompt",
            system_message: nil,
            model: "claude-3-sonnet",
            temperature: nil,
            max_tokens: nil,
            parameters_used: {},
            version_number: 1
          }
        end

        it "removes nil values with compact" do
          prompt_with_nils = described_class.new(prompt, rendered_data_with_nils)
          params = prompt_with_nils.to_ruby_llm_params

          expect(params).to eq({
            messages: [
              { role: "user", content: "Test prompt" }
            ],
            model: "claude-3-sonnet"
          })
          expect(params).not_to have_key(:temperature)
          expect(params).not_to have_key(:max_tokens)
        end
      end

      context "with additional options" do
        let(:test_rendered_data) do
          {
            content: "Test prompt",
            system_message: "You are helpful",
            model: "claude-3-opus",
            temperature: 0.7,
            max_tokens: 1000,
            parameters_used: {},
            version_number: 1
          }
        end

        it "merges additional options into the parameters" do
          prompt_test = described_class.new(prompt, test_rendered_data)
          params = prompt_test.to_ruby_llm_params(
            stop_sequences: [ "\\n\\n" ],
            top_p: 0.9,
            metadata: { user_id: 123 }
          )

          expect(params).to include(
            messages: anything,
            model: "claude-3-opus",
            temperature: 0.7,
            max_tokens: 1000,
            stop_sequences: [ "\\n\\n" ],
            top_p: 0.9,
            metadata: { user_id: 123 }
          )
        end

        it "allows additional options to override base parameters" do
          prompt_test = described_class.new(prompt, test_rendered_data)
          params = prompt_test.to_ruby_llm_params(
            model: "claude-3-haiku",
            temperature: 0.2
          )

          expect(params[:model]).to eq("claude-3-haiku")
          expect(params[:temperature]).to eq(0.2)
        end
      end

      context "with overrides from constructor" do
        let(:test_rendered_data) do
          {
            content: "Test prompt",
            system_message: "Original system",
            model: "claude-3-opus",
            temperature: 0.7,
            max_tokens: 1000,
            parameters_used: {},
            version_number: 1
          }
        end

        let(:test_overrides) do
          {
            model: "claude-3-sonnet",
            temperature: 0.4,
            max_tokens: 2000,
            system_message: "Override system"
          }
        end

        it "uses override values in the output" do
          prompt_with_overrides = described_class.new(prompt, test_rendered_data, test_overrides)
          params = prompt_with_overrides.to_ruby_llm_params

          expect(params).to eq({
            messages: [
              { role: "system", content: "Override system" },
              { role: "user", content: "Test prompt" }
            ],
            model: "claude-3-sonnet",
            temperature: 0.4,
            max_tokens: 2000
          })
        end
      end

      context "compatibility with Anthropic format" do
        it "produces the same structure as expected by Anthropic clients" do
          prompt_test = described_class.new(prompt, rendered_data)
          params = prompt_test.to_ruby_llm_params

          # Anthropic expects the same format
          expect(params).to have_key(:messages)
          expect(params).to have_key(:model)
          expect(params[:messages]).to be_an(Array)
          expect(params[:messages].first).to have_key(:role)
          expect(params[:messages].first).to have_key(:content)
        end
      end

      # THE key regression-pinning area (CVP-1797): reasoning_effort is an
      # OpenAI-only wire parameter. ruby_llm's Anthropic provider never
      # accepts a top-level reasoning_effort: key - the real channel is
      # with_thinking (reasoning_thinking_args), driven separately by
      # execute_with. This regressed twice across code review: once by
      # leaking it unconditionally, once more narrowly for effort-mode
      # Anthropic families specifically (budget-mode alone was fixed first).
      context "with a reasoning-capable Anthropic model (regression guard)" do
        it "never includes reasoning_effort for an effort-mode family (e.g. claude-opus-4-8)" do
          data = {
            content: "Test prompt",
            system_message: "You are helpful",
            model: "claude-opus-4-8",
            temperature: 0.7,
            max_tokens: 1000,
            reasoning_effort: "high",
            parameters_used: {},
            version_number: 1
          }
          rp = described_class.new(prompt, data)

          expect(rp.to_ruby_llm_params).not_to have_key(:reasoning_effort)
        end

        it "never includes reasoning_effort for a budget-mode family (e.g. claude-haiku-4-5)" do
          data = {
            content: "Test prompt",
            system_message: "You are helpful",
            model: "claude-haiku-4-5",
            temperature: 0.7,
            max_tokens: 1000,
            reasoning_effort: "medium",
            parameters_used: {},
            version_number: 1
          }
          rp = described_class.new(prompt, data)

          expect(rp.to_ruby_llm_params).not_to have_key(:reasoning_effort)
        end

        it "does not include the non-wire-parameter reasoning_thinking_args key either" do
          data = {
            content: "Test prompt",
            system_message: "You are helpful",
            model: "claude-opus-4-8",
            temperature: 0.7,
            max_tokens: 1000,
            reasoning_effort: "high",
            parameters_used: {},
            version_number: 1
          }
          rp = described_class.new(prompt, data)

          expect(rp.to_ruby_llm_params).not_to have_key(:reasoning_thinking_args)
        end
      end
    end

    describe "#execute_with" do
      let(:test_rendered_data) do
        {
          content: "Test prompt",
          system_message: "Test system",
          model: "gpt-4",
          temperature: 0.7,
          max_tokens: 1000,
          parameters_used: {},
          version_number: 1
        }
      end

      let(:rendered_prompt) { described_class.new(prompt, test_rendered_data) }

      context "with OpenAI client" do
        let(:openai_client) do
          client_class = double("Class", name: "OpenAI::Client")
          double("OpenAI::Client", class: client_class)
        end

        it "detects OpenAI client and calls chat with parameters key" do
          expected_params = {
            model: "gpt-4",
            messages: [
              { role: "system", content: "Test system" },
              { role: "user", content: "Test prompt" }
            ],
            temperature: 0.7,
            max_tokens: 1000
          }

          expect(openai_client).to receive(:chat).with(parameters: expected_params)
          rendered_prompt.execute_with(openai_client)
        end

        it "passes additional options to OpenAI parameters" do
          expect(openai_client).to receive(:chat).with(
            parameters: hash_including(stream: true, tools: [ "test" ])
          )

          rendered_prompt.execute_with(openai_client, stream: true, tools: [ "test" ])
        end

        it "works with different OpenAI client class names" do
          [ "OpenAI", "MyOpenAIWrapper", "CustomOpenAIClient" ].each do |class_name|
            client_class = double("Class", name: class_name)
            client = double(class_name, class: client_class)

            expect(client).to receive(:chat).with(parameters: anything)
            rendered_prompt.execute_with(client)
          end
        end
      end

      context "with Anthropic client" do
        let(:anthropic_client) do
          client_class = double("Class", name: "Anthropic::Client")
          double("Anthropic::Client", class: client_class)
        end

        it "detects Anthropic client and calls chat with splatted parameters" do
          expected_params = {
            messages: [
              { role: "system", content: "Test system" },
              { role: "user", content: "Test prompt" }
            ],
            model: "gpt-4",
            temperature: 0.7,
            max_tokens: 1000
          }

          expect(anthropic_client).to receive(:chat).with(**expected_params)
          rendered_prompt.execute_with(anthropic_client)
        end

        it "passes additional options to Anthropic parameters" do
          expect(anthropic_client).to receive(:chat).with(
            hash_including(stop_sequences: [ "\\n" ], metadata: { user: "test" })
          )

          rendered_prompt.execute_with(anthropic_client, stop_sequences: [ "\\n" ], metadata: { user: "test" })
        end

        it "works with different Anthropic client class names" do
          [ "Anthropic", "AnthropicAPI", "MyAnthropicWrapper" ].each do |class_name|
            client_class = double("Class", name: class_name)
            client = double(class_name, class: client_class)

            expect(client).to receive(:chat).with(anything)
            rendered_prompt.execute_with(client)
          end
        end
      end

      context "with RubyLLM client" do
        let(:ruby_llm_client) do
          client_class = double("Class", name: "RubyLLM::Provider")
          double("RubyLLM::Provider", class: client_class)
        end

        it "detects RubyLLM client and calls chat with splatted parameters" do
          expected_params = {
            messages: [
              { role: "system", content: "Test system" },
              { role: "user", content: "Test prompt" }
            ],
            model: "gpt-4",
            temperature: 0.7,
            max_tokens: 1000
          }

          expect(ruby_llm_client).to receive(:chat).with(**expected_params)
          rendered_prompt.execute_with(ruby_llm_client)
        end

        it "passes additional options to RubyLLM parameters" do
          expect(ruby_llm_client).to receive(:chat).with(
            hash_including(provider_options: { api_key: "test" })
          )

          rendered_prompt.execute_with(ruby_llm_client, provider_options: { api_key: "test" })
        end

        it "works with different RubyLLM client class names" do
          [ "RubyLLM", "RubyLLMClient", "MyRubyLLMProvider" ].each do |class_name|
            client_class = double("Class", name: class_name)
            client = double(class_name, class: client_class)

            expect(client).to receive(:chat).with(anything)
            rendered_prompt.execute_with(client)
          end
        end
      end

      context "dispatch to with_thinking for reasoning-capable models" do
        let(:ruby_llm_client) do
          client_class = double("Class", name: "RubyLLM::Provider")
          double("RubyLLM::Provider", class: client_class)
        end

        it "sends chat through the object returned by with_thinking for an effort-mode model" do
          data = test_rendered_data.merge(model: "claude-opus-4-8", reasoning_effort: "xhigh")
          rp = described_class.new(prompt, data)

          thinking_target = double("thinking-target")
          allow(ruby_llm_client).to receive(:with_thinking).with(effort: "xhigh").and_return(thinking_target)
          expect(thinking_target).to receive(:chat)
          expect(ruby_llm_client).not_to receive(:chat)

          rp.execute_with(ruby_llm_client)
        end

        it "sends chat through the object returned by with_thinking for a budget-mode model" do
          data = test_rendered_data.merge(model: "claude-haiku-4-5", reasoning_effort: "medium")
          rp = described_class.new(prompt, data)

          thinking_target = double("thinking-target")
          allow(ruby_llm_client).to receive(:with_thinking).with(budget: 8192).and_return(thinking_target)
          expect(thinking_target).to receive(:chat)
          expect(ruby_llm_client).not_to receive(:chat)

          rp.execute_with(ruby_llm_client)
        end

        it "calls chat directly on the client for a non-reasoning model, without calling with_thinking" do
          data = test_rendered_data.merge(model: "gpt-4", reasoning_effort: nil)
          rp = described_class.new(prompt, data)

          expect(ruby_llm_client).not_to receive(:with_thinking)
          expect(ruby_llm_client).to receive(:chat)

          rp.execute_with(ruby_llm_client)
        end
      end

      context "with unknown client" do
        let(:unknown_client) do
          client_class = double("Class", name: "RandomAPI::Client")
          double("RandomAPI::Client", class: client_class)
        end

        it "raises ArgumentError for unrecognized client type" do
          expect {
            rendered_prompt.execute_with(unknown_client)
          }.to raise_error(ArgumentError, "Unknown client type: RandomAPI::Client")
        end

        it "includes the class name in the error message" do
          [ "SomeOtherClient", "UnknownProvider", "CustomLLM" ].each do |class_name|
            client_class = double("Class", name: class_name)
            client = double(class_name, class: client_class)

            expect {
              rendered_prompt.execute_with(client)
            }.to raise_error(ArgumentError, "Unknown client type: #{class_name}")
          end
        end
      end

      context "integration with parameter methods" do
        it "calls to_openai_params for OpenAI clients" do
          client_class = double("Class", name: "OpenAI::Client")
          client = double("OpenAI::Client", class: client_class)

          expect(rendered_prompt).to receive(:to_openai_params).with(test: true).and_call_original
          expect(client).to receive(:chat).with(parameters: anything)

          rendered_prompt.execute_with(client, test: true)
        end

        it "calls to_ruby_llm_params for RubyLLM clients" do
          client_class = double("Class", name: "RubyLLM::Provider")
          client = double("RubyLLM::Provider", class: client_class)

          expect(rendered_prompt).to receive(:to_ruby_llm_params).with(test: true).and_call_original
          expect(client).to receive(:chat).with(anything)

          rendered_prompt.execute_with(client, test: true)
        end

        it "calls to_ruby_llm_params for Anthropic clients" do
          client_class = double("Class", name: "Anthropic::Client")
          client = double("Anthropic::Client", class: client_class)

          expect(rendered_prompt).to receive(:to_ruby_llm_params).with(test: true).and_call_original
          expect(client).to receive(:chat).with(anything)

          rendered_prompt.execute_with(client, test: true)
        end
      end
    end
  end
end
