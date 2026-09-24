module PromptEngine
  class RenderedPrompt
    attr_reader :prompt, :content, :overrides,
                :version_number

    def initialize(prompt, rendered_data, overrides = {})
      @prompt = prompt
      @content = rendered_data[:content]
      @parameters = rendered_data[:parameters_used] || {}
      @overrides = overrides
      @version_number = rendered_data[:version_number]
      @rendered_data = rendered_data

      # Store status - use override if provided, otherwise use prompt's current status
      # Note: When a specific version is loaded, we still use the current prompt status
      # unless explicitly overridden
      @status = overrides.key?(:status) ? overrides[:status] : prompt.status
    end

    # Options accessor - returns the options hash used for rendering
    def options
      @overrides.dup
    end

    # Individual accessors for common options
    def status
      @status
    end

    def version
      @version_number
    end

    def model
      @overrides[:model] || @rendered_data[:model]
    end

    def temperature
      @overrides[:temperature] || @rendered_data[:temperature]
    end

    def max_tokens
      @overrides[:max_tokens] || @rendered_data[:max_tokens]
    end

    # The named effort-level string, for OpenAI's `reasoning_effort:` wire
    # parameter (see `to_openai_params`). `reasoning_effort` is an
    # OpenAI-only wire parameter - `ruby_llm`'s Anthropic provider never
    # accepts a top-level `reasoning_effort:` key (it uses `thinking:` /
    # `output_config: {effort:}` internally, driven by `with_thinking`; see
    # `reasoning_thinking_args` and `execute_with` below). Only meaningful
    # for "effort"-mode model families - returns nil for "budget"-mode
    # families (e.g. claude-haiku-4-5), whose value is a *token count*, not
    # this string.
    #
    # Resolved against `model` (the override-aware accessor above), so an
    # `options: { model: ... }` override reconciles correctly and a value
    # is always returned for reasoning-capable effort-mode models
    # (request-time default).
    def reasoning_effort
      return nil unless PromptEngine::Reasoning.config_for(model)&.fetch(:mode, nil) == "effort"

      PromptEngine::Reasoning.resolve(model, @overrides[:reasoning_effort] || @rendered_data[:reasoning_effort])
    end

    # The keyword arguments to splat into `chat.with_thinking(...)`, or nil
    # when `model` supports no reasoning.
    def reasoning_thinking_args
      PromptEngine::Reasoning.thinking_args(model, @overrides[:reasoning_effort] || @rendered_data[:reasoning_effort])
    end

    def system_message
      @overrides[:system_message] || @rendered_data[:system_message]
    end

    # Returns messages array for chat-based models
    def messages
      msgs = []
      msgs << { role: "system", content: system_message } if system_message.present?
      msgs << { role: "user", content: content }
      msgs
    end

    # For OpenAI gem compatibility
    def to_openai_params(**additional_options)
      base_params = {
        model: model || "gpt-4",
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        reasoning_effort: reasoning_effort
      }.compact

      # Merge with additional options (tools, functions, response_format, etc.)
      base_params.merge(additional_options)
    end

    # For RubyLLM compatibility. Deliberately carries NO `reasoning_effort:`
    # key, for ANY model family (effort-mode or budget-mode) - unlike
    # `to_openai_params`, `reasoning_effort` is an OpenAI-only wire
    # parameter, and `ruby_llm`'s Anthropic provider never accepts a
    # top-level `reasoning_effort:` key. The real reasoning channel for
    # `ruby_llm`/Anthropic is `with_thinking` (`thinking:` /
    # `output_config: {effort:}` under the hood), driven by
    # `reasoning_thinking_args` below - NOT a wire parameter, and
    # intentionally excluded from this hash (and from `to_h`) because it
    # gets splatted directly into `client.chat(**params)` in `execute_with`,
    # and a client with a strict kwargs signature would raise
    # `ArgumentError: unknown keyword: :reasoning_thinking_args`. Call the
    # `reasoning_thinking_args` reader directly and pass it to
    # `chat.with_thinking(**...)` instead - see `execute_with` below.
    def to_ruby_llm_params(**additional_options)
      base_params = {
        messages: messages,
        model: model || "gpt-4",
        temperature: temperature,
        max_tokens: max_tokens
      }.compact

      # Merge with additional options
      base_params.merge(additional_options)
    end

    # Automatic client detection and execution
    def execute_with(client, **options)
      case client.class.name
      when /OpenAI/
        params = to_openai_params(**options)
        client.chat(parameters: params)
      when /RubyLLM/, /Anthropic/
        params = to_ruby_llm_params(**options)
        args = reasoning_thinking_args
        target = args && client.respond_to?(:with_thinking) ? client.with_thinking(**args) : client
        target.chat(**params)
      else
        raise ArgumentError, "Unknown client type: #{client.class.name}"
      end
    end

    # Parameter access methods
    def parameters
      @parameters
    end

    def parameter(key)
      @parameters[key.to_s]
    end

    def parameter_names
      @parameters.keys
    end

    def parameter_values
      @parameters.values
    end

    # Check if a parameter exists
    def parameter?(key)
      @parameters.key?(key.to_s)
    end

    # Convenience methods. Deliberately carries NO `reasoning_effort:` key -
    # like `to_ruby_llm_params`, that wire parameter is OpenAI-only (see
    # `to_openai_params`); merging it here for every provider, including
    # Anthropic's effort-mode families (e.g. claude-opus-4-8), would be
    # both redundant (the real mechanism is `with_thinking`, driven by
    # `reasoning_thinking_args`) and wrong for a caller that splats this
    # hash directly at an Anthropic client. `reasoning_thinking_args` is
    # deliberately NOT included here either - it is not a wire parameter,
    # only a reader for callers that want to call
    # `chat.with_thinking(**...)` themselves; see the comment on
    # `to_ruby_llm_params` above.
    def to_h
      {
        content: content,
        system_message: system_message,
        model: model,
        temperature: temperature,
        max_tokens: max_tokens,
        messages: messages,
        options: options,
        status: status,
        version: version,
        parameters: parameters
      }
    end

    def inspect
      version_info = version_number ? " version=#{version_number}" : ""
      param_info = parameter_names.any? ? " parameters=#{parameter_names}" : ""
      override_info = overrides.any? ? " overrides=#{overrides.keys}" : ""
      "#<PromptEngine::RenderedPrompt prompt=#{prompt.slug}#{version_info}#{param_info}#{override_info}>"
    end
  end
end
