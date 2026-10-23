# PromptEngine.configuration is a process-wide singleton, and several specs
# mutate it (PromptEngine.configure, model_provider_patterns["openai"] = ...,
# model_reasoning_options["my-llm"] = ...). A spec that forgets to restore it
# leaks into every later example: the "configure" spec's one-model allowlist
# made every later PlaygroundExecutor spec raise "Unsupported model: gpt-4o"
# (CVP-1821). Resetting to a fresh Configuration after each example makes that
# leak impossible, whatever order the specs run in. The dummy app configures
# nothing, so a fresh instance is the correct baseline.
RSpec.configure do |config|
  config.after do
    PromptEngine.instance_variable_set(:@configuration, nil)
  end
end
