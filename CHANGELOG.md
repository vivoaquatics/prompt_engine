# Changelog

All notable changes to PromptEngine will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Model-aware `reasoning_effort` option on prompts, versioned and forwarded to
  `ruby_llm` at request time (defaults to `low` for reasoning-capable
  models).
  - **Migration required.** Adds a nullable `reasoning_effort` string column
    to `prompt_engine_prompts`, `prompt_engine_prompt_versions`, and
    `prompt_engine_playground_run_results`. Host apps must run
    `bin/rails prompt_engine:install:migrations && bin/rails db:migrate`
    after upgrading to this version. If the gem is updated before the
    migration runs, the engine degrades gracefully (reasoning_effort reads
    as nil / writes no-op) rather than raising across the whole prompts UI -
    see `PromptEngine::ReasoningColumnGuard`.
- Flexible authentication system with multiple strategies
  - HTTP Basic authentication with secure credential comparison
  - Integration with host app authentication (Devise, custom auth)
  - ActiveSupport hooks for custom authentication logic
  - Rack middleware support for advanced scenarios
- Configuration API for authentication settings
  - `PromptEngine.configure` block for easy setup
  - Environment-specific authentication configuration
  - Ability to disable authentication for development
- Comprehensive authentication documentation
  - Detailed setup guide in README
  - Dedicated AUTHENTICATION.md with examples and best practices
  - Security recommendations and troubleshooting tips
- Authentication test suite with full coverage

### Removed
- **BREAKING:** `PromptEngine::Setting#masked_openai_api_key`, `#masked_anthropic_api_key`, and
  the private `#mask_api_key` have been removed. They rendered a prefix and suffix of a live API
  key and had no remaining caller in the engine. A host application that overrode
  `app/views/prompt_engine/settings/edit.html.erb` and called either method will raise
  `NoMethodError` after upgrading; replace the call with `Setting#openai_configured?` /
  `#anthropic_configured?`, which return a boolean and never expose key material. This is a
  MAJOR-version-worthy breaking change under the SemVer policy declared above.

### Security
- Uses `ActiveSupport::SecurityUtils.secure_compare` to prevent timing attacks
- Credentials are never logged or exposed in error messages
- Authentication is enabled by default (must be explicitly disabled)
- Playground no longer renders stored OpenAI/Anthropic API keys into the page HTML (form
  field values and `data-` attributes). Keys are resolved server-side from
  `PromptEngine::Setting` based on the provider inferred from the selected model.
- The engine now appends `:api_key` to the host application's `config.filter_parameters`.
  This only protects hosts that append to the default filter list; a host that fully
  *replaces* `config.filter_parameters` after this initializer runs will still not redact
  `:api_key`.
- Playground API keys are now applied through a per-call `RubyLLM.context` instead of the
  process-wide `RubyLLM.config`, so a key supplied for one request can no longer be observed
  by a concurrent request or persist as the host application's default.
- The playground now raises an explicit "Unsupported provider" error when a
  host-configured `model_provider_patterns` entry maps to a provider outside
  `anthropic`/`openai`, instead of silently falling through. Previously, a host with a
  custom pattern for a provider outside this list, combined with a global RubyLLM key
  already configured for that provider (via the host's own `RubyLLM.configure`), would
  have that global key used by the playground's chat call rather than being rejected.
- The Settings page no longer displays any portion of a stored API key (previously the
  password field's placeholder showed a masked value, e.g. `sk-...789`, once a key was
  configured). It now shows a value-free "API key is saved" placeholder instead, driven by
  `Setting#openai_configured?`/`#anthropic_configured?`. See the `### Removed` section above
  for the corresponding removal of `#masked_openai_api_key`/`#masked_anthropic_api_key`.
- The Settings UI no longer offers a "remove key" control. Clearing a stored API key is now
  a console-only operation: `PromptEngine::Setting.instance.update!(openai_api_key: nil)`
  (or `anthropic_api_key: nil`). The invariant that an empty-string submission from the web
  form never overwrites an already-stored key lives on `PromptEngine::Setting` itself (a
  `before_validation` callback,
  `PromptEngine::Setting#retain_existing_api_keys_when_blank`), not only in the
  controller's strong parameters, so any writer - console, seeds, a future API - gets the
  same protection. This check treats any String Rails considers `.blank?` (empty,
  ASCII-whitespace-only, or Unicode-whitespace-only) as "leave unchanged"; only a non-String
  `nil` (only reachable outside the web form, e.g. from a console or service-object caller)
  still clears the key.
- Both Settings API key fields now use `autocomplete: "new-password"` instead of
  `autocomplete: "off"`, matching the Playground fix; `off` is routinely ignored by browser
  password managers on `type=password` inputs.
- The README's authentication section is now explicit that PromptEngine ships with no
  authentication of its own and that configuring it is required (not merely recommended)
  before mounting the engine anywhere beyond local development.
- **Security (action required):** Rotate your stored OpenAI and Anthropic API keys after
  upgrading. Prior versions rendered them into the playground page HTML, so any key stored
  in `PromptEngine::Setting` must be assumed disclosed to anyone who loaded that page or has
  a saved/proxied copy of its response. Upgrading stops further exposure but does not
  invalidate keys already exposed.

### Fixed
- `PromptEngine::SettingsController#update` no longer overwrites a stored, encrypted
  provider API key with a blank value when only the OTHER provider's field is submitted.
  Password fields are deliberately never prefilled, so both fields POST on every save;
  previously, saving a new OpenAI key (for example) silently wiped the already-configured
  Anthropic key, and vice versa, with no confirmation and no way to recover a
  provider-issued secret shown only once at creation. Any String Rails considers `.blank?`
  (empty, ASCII-whitespace-only, or Unicode-whitespace-only) submitted for a provider's
  field is now retained as the existing stored key by
  `PromptEngine::Setting#retain_existing_api_keys_when_blank` (a model-level
  `before_validation` callback), so submitting a field blank leaves that provider's stored
  key unchanged, matching the on-screen "Leave a field empty to keep its existing value
  unchanged" note. For a provider that has never had a key configured, a blank submission
  now normalizes the stored value to `nil`/`NULL` rather than persisting a literal encrypted
  empty string, so downstream `||`-chained credentials fallbacks (e.g.
  `PromptEngine::OpenAiEvalsClient#initialize`) are not short-circuited by a falsy-looking
  but truthy `""`.

### Changed
- `PlaygroundExecutor#initialize`'s `api_key:` keyword is now optional and defaults to
  `nil`. `nil`/blank means "resolve from `PromptEngine::Setting` only" — there is no
  `Rails.application.credentials` fallback. Passing an explicit non-blank value still
  overrides. Existing callers are unaffected.
- The playground form no longer requires an `api_key` parameter; it is submitted only when
  the user types an explicit override.
- `PlaygroundExecutor` now reads the `Setting` singleton with `Setting.first` (read-only)
  rather than `Setting.instance` (`first_or_create!`), so submitting the playground before
  any Setting row exists no longer creates one as a side effect.

## [1.0.0] - 2025-01-24

### Added
- Initial release of PromptEngine
- Core prompt management functionality
  - Create, edit, and organize prompts with slug-based identification
  - Automatic variable detection with `{{variable}}` syntax
  - Version control with automatic versioning and rollback
  - Parameter type detection and validation
- Admin interface
  - Modern, responsive UI design
  - Prompt playground for testing with real AI providers
  - Version comparison and history
  - Status management (draft, active, archived)
- AI Provider Integration
  - Support for OpenAI and Anthropic
  - Configurable model settings (temperature, max_tokens, etc.)
  - Secure API key storage using Rails encryption
- Developer API
  - Simple integration: `PromptEngine.render(:prompt_slug, variables: {})`
  - Direct LLM integration support
  - Override model settings at runtime
- Testing Infrastructure
  - RSpec test suite
  - VCR for API testing
  - Factory Bot for test data
- Documentation
  - Comprehensive README
  - Architecture documentation
  - API usage examples