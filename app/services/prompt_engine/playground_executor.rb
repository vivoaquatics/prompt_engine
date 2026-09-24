module PromptEngine
  class PlaygroundExecutor
    # Providers for which this engine can resolve a stored key. Enforced by
    # validate_inputs! before any resolution happens (CVP-1822): a
    # host-configured provider outside this list raises instead of silently
    # resolving to nil (or, previously, to some other provider's key).
    SETTINGS_KEY_PROVIDERS = %w[anthropic openai].freeze

    attr_reader :prompt, :api_key, :parameters, :model

    def initialize(prompt:, api_key: nil, parameters: {}, model: nil)
      @prompt = prompt
      @api_key = api_key.is_a?(String) ? api_key.presence : nil
      @parameters = parameters || {}
      @model = model.presence
    end

    # Excludes resolved/submitted key material from #inspect (and anything else
    # that walks instance_variables), mirroring RubyLLM::Chat#instance_variables
    # and RubyLLM::Connection#instance_variables (ruby_llm gem, same rationale:
    # never let a credential leak through a log/inspect call) (CVP-1822).
    def instance_variables
      super - %i[@api_key @resolved_api_key]
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

      # Build a request-scoped context carrying the resolved API key, then start
      # the chat from it (never RubyLLM.chat, which uses global config).
      chat = llm_context.chat(model: selected_model)

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
        provider: provider
      }
    rescue => e
      handle_error(e)
    end

    private

    def validate_inputs!
      raise ArgumentError, "Model is required" if selected_model.blank?
      raise ArgumentError, "Unsupported model: #{selected_model}" if provider.blank?
      unless SETTINGS_KEY_PROVIDERS.include?(provider)
        raise ArgumentError, "Unsupported provider: #{provider}"
      end
      raise ArgumentError, "API key is required" if resolved_api_key.blank?
    end

    # Resolution order: explicit caller override, then the encrypted Setting for the
    # inferred provider. No Rails credentials fallback (CVP-1822): a host that wants
    # a hard-coded fallback key can still pass api_key: explicitly.
    def resolved_api_key
      @resolved_api_key ||= api_key.presence || settings_api_key
    end

    def settings_api_key
      return nil unless SETTINGS_KEY_PROVIDERS.include?(provider)

      # Read-only lookup (CVP-1822): unlike Setting.instance (first_or_create!),
      # this never creates a Setting row from the playground's POST path.
      PromptEngine::Setting.first&.public_send(:"#{provider}_api_key")&.presence
    end

    # Per-call context, not global config: RubyLLM.context dups the global config
    # and scopes our key to this one chat, so a concurrent request (or the host
    # app's own RubyLLM usage) can never pick up this request's key (CVP-1822).
    def llm_context
      require "ruby_llm"

      key = resolved_api_key
      RubyLLM.context do |config|
        case provider
        when "anthropic"
          config.anthropic_api_key = key
        when "openai"
          config.openai_api_key = key
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
