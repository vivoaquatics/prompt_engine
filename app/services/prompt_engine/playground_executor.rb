module PromptEngine
  class PlaygroundExecutor
    attr_reader :prompt, :api_key, :parameters, :model

    def initialize(prompt:, api_key:, parameters: {}, model: nil)
      @prompt = prompt
      @api_key = api_key
      @parameters = parameters || {}
      @model = model.presence
    end

    # The model that will actually be used for this run: the override if one
    # was supplied, otherwise the prompt's saved model. The saved prompt is
    # never modified.
    def selected_model
      model || prompt.model
    end

    # The provider is inferred from the selected model id (using the
    # end-user-configurable PromptEngine.configuration.model_provider_patterns),
    # so callers only need to choose a model. Returns nil for unmappable models.
    def provider
      @provider ||= PromptEngine.configuration.model_provider_patterns
        .find { |_name, pattern| selected_model.to_s.match?(pattern) }&.first
    end

    def execute
      validate_inputs!

      start_time = Time.current

      # Replace parameters in prompt content
      parser = ParameterParser.new(prompt.content)
      processed_content = parser.replace_parameters(parameters)

      # Configure RubyLLM with the appropriate API key
      configure_ruby_llm

      # Create chat instance with the selected model (override or provider default)
      chat = build_chat
      chat = apply_reasoning(chat)

      # Apply temperature if specified
      if prompt.temperature.present?
        chat = chat.with_temperature(prompt.temperature)
      end

      # Apply system message if present
      if prompt.system_message.present?
        chat = chat.with_instructions(prompt.system_message)
      end

      # Execute the prompt
      # Note: max_tokens may need to be passed differently depending on RubyLLM version
      response = chat.ask(processed_content)

      execution_time = (Time.current - start_time).round(3)

      # Handle response based on its structure
      response_content = if response.respond_to?(:content)
        response.content
      elsif response.is_a?(String)
        response
      else
        response.to_s
      end

      # Try to get token count if available
      token_count = if response.respond_to?(:input_tokens) && response.respond_to?(:output_tokens)
        (response.input_tokens || 0) + (response.output_tokens || 0)
      else
        0 # Default if token information isn't available
      end

      {
        response: response_content,
        execution_time: execution_time,
        token_count: token_count,
        model: selected_model,
        provider: provider,
        reasoning_effort: resolved_reasoning_effort
      }
    rescue => e
      handle_error(e)
    end

    private

    # The reasoning effort actually sent with this run: the prompt's saved
    # value if valid for the selected model, otherwise the request-time
    # default, otherwise nil for models that support no reasoning.
    def resolved_reasoning_effort
      @resolved_reasoning_effort ||= PromptEngine::Reasoning.resolve(selected_model, prompt.reasoning_effort)
    end

    # Guarded by respond_to? because the gemspec places no floor on ruby_llm;
    # a host app on an older version degrades to today's behaviour (nothing
    # sent) instead of NoMethodError.
    def apply_reasoning(chat)
      return chat unless chat.respond_to?(:with_thinking)

      args = PromptEngine::Reasoning.thinking_args(selected_model, prompt.reasoning_effort)
      return chat unless args

      chat.with_thinking(**args)
    end

    # ruby_llm resolves model ids against its bundled registry (models.json), which
    # lags provider releases. When a configured model id is not in that registry we
    # retry with assume_model_exists:, passing the provider we already inferred from
    # PromptEngine.configuration.model_provider_patterns. Known models keep their
    # full registry metadata; only unknown ids take the assumed path.
    def build_chat
      RubyLLM.chat(model: selected_model)
    rescue RubyLLM::ModelNotFoundError
      RubyLLM.chat(model: selected_model, provider: provider, assume_model_exists: true)
    end

    def validate_inputs!
      raise ArgumentError, "Model is required" if selected_model.blank?
      raise ArgumentError, "API key is required" if api_key.blank?
      raise ArgumentError, "Unsupported model: #{selected_model}" if provider.blank?

      allowed_models = PromptEngine.configuration.options_for_model_select.map(&:last)
      unless allowed_models.include?(selected_model)
        raise ArgumentError, "Unsupported model: #{selected_model}"
      end
    end

    def configure_ruby_llm
      require "ruby_llm"

      RubyLLM.configure do |config|
        case provider
        when "anthropic"
          config.anthropic_api_key = api_key
        when "openai"
          config.openai_api_key = api_key
        end
      end
    end

    def handle_error(error)
      # Re-raise ArgumentError as-is for validation errors
      raise error if error.is_a?(ArgumentError)

      # Check for specific error types first
      case error
      when Net::HTTPUnauthorized
        raise "Invalid API key"
      when Net::HTTPTooManyRequests
        raise "Rate limit exceeded. Please try again later."
      when Net::HTTPError
        raise "Network error. Please check your connection and try again."
      else
        # Then check error message patterns
        error_message = error.message.to_s
        case error_message
        when /unauthorized/i
          raise "Invalid API key"
        when /rate limit/i
          raise "Rate limit exceeded. Please try again later."
        when /network/i
          raise "Network error. Please check your connection and try again."
        else
          raise "An error occurred: #{error.message}"
        end
      end
    end
  end
end
