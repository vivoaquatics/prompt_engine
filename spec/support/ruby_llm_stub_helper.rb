# CVP-1822: PlaygroundExecutor scopes its API key through a per-call
# RubyLLM.context (never RubyLLM.configure/.chat) so a key applied for one
# request cannot leak into a concurrent request or the host app's own RubyLLM
# usage. Every spec that exercises PlaygroundExecutor#execute must stub
# RubyLLM.context accordingly.
#
# IMPORTANT: `RubyLLM.context` collides with RSpec's own `Module#context` DSL
# alias. A bare `Module.new` (or any real Module/Class) responds to `.context`
# out of the box via that alias, so a stub that forgets to define `.context`
# does NOT raise -- it silently opens a new (never-run) nested example group
# instead of exercising the key-application code, and the spec can look green
# while testing nothing. Using `class_double(RubyLLM)` (a verifying double,
# not a real Module) closes that hole: any message not explicitly stubbed
# raises, including `.context`.
#
# Required at file-load time (not lazily inside the helper method) so that
# `RubyLLM::Chat` / `RubyLLM::Configuration` / `RubyLLM::Context` are already
# defined constants by the time a spec's `let(:mock_chat) { instance_double(RubyLLM::Chat) }`
# is evaluated -- `instance_double`/`class_double` need the real constant loaded
# to verify against.
require "ruby_llm"

# Captured before any spec stubs the top-level `RubyLLM` constant. Once
# `class_double(RubyLLM).as_stubbed_const` has run, a bareword `RubyLLM::Chat`
# reference resolves against the *double*, not the real module, and raises
# `NameError: uninitialized constant ...::Chat`. Specs that need to build a
# fresh `instance_double` after an earlier `stub_ruby_llm_context!` call in
# the same example should use these constants instead of `RubyLLM::Chat` etc.
RUBY_LLM_MODULE = RubyLLM
RUBY_LLM_CHAT_CLASS = RubyLLM::Chat
RUBY_LLM_CONFIGURATION_CLASS = RubyLLM::Configuration
RUBY_LLM_CONTEXT_CLASS = RubyLLM::Context

module RubyLLMStubHelper
  # Stubs RubyLLM.context to yield a per-call config double and return a
  # context double whose #chat returns chat_double. Returns the doubles so
  # callers can assert on them (e.g. `expect(ruby_llm[:config]).to
  # have_received(:openai_api_key=).with("sk-...")`).
  def stub_ruby_llm_context!(chat_double: nil)
    config_double = instance_double(RUBY_LLM_CONFIGURATION_CLASS)
    allow(config_double).to receive(:anthropic_api_key=)
    allow(config_double).to receive(:openai_api_key=)

    # The process-wide config. Must never receive a key setter -- that is the
    # whole point of the per-call context (CVP-1822 / matrix row A11).
    global_config = instance_double(RUBY_LLM_CONFIGURATION_CLASS)
    allow(global_config).to receive(:anthropic_api_key=)
    allow(global_config).to receive(:openai_api_key=)

    context_double = instance_double(RUBY_LLM_CONTEXT_CLASS)
    chat_double ||= instance_double(RUBY_LLM_CHAT_CLASS)
    allow(context_double).to receive(:chat).and_return(chat_double)

    ruby_llm = class_double(RUBY_LLM_MODULE).as_stubbed_const
    allow(ruby_llm).to receive(:context).and_yield(config_double).and_return(context_double)
    allow(ruby_llm).to receive(:config).and_return(global_config)

    {
      module: ruby_llm,
      config: config_double,
      global_config: global_config,
      context: context_double,
      chat: chat_double
    }
  end
end

RSpec.configure do |config|
  config.include RubyLLMStubHelper
end
