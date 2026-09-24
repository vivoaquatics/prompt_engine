module PromptEngine
  class Setting < ApplicationRecord
    self.table_name = "prompt_engine_settings"

    # Rails automatically encrypts these attributes
    encrypts :openai_api_key
    encrypts :anthropic_api_key

    API_KEY_ATTRIBUTES = %i[openai_api_key anthropic_api_key].freeze

    # Domain invariant: a blank or whitespace-only String submitted value for
    # a provider's API key attribute never overwrites an already-persisted
    # key - password fields are never prefilled, so both fields POST on every
    # save, and an empty or whitespace-only string from the web form means
    # "leave unchanged", not "clear". Any String Rails considers blank?
    # (empty, ASCII-whitespace-only, or Unicode-whitespace-only) means leave
    # the key unchanged; only a non-String nil clears it. `nil` is not a
    # String, so it is treated as an explicit clear request and is exempt
    # from this guard: `Setting.instance.update!(openai_api_key: nil)` from a
    # console or a service object still clears the key. Console-based `nil`
    # assignment is the only supported way to remove a stored key now that
    # the Settings UI has no "remove key" control. This guard lives on the
    # model (not the controller) so every writer - console, seeds, a future
    # API - gets the same protection.
    before_validation :retain_existing_api_keys_when_blank

    # Singleton pattern - only one settings record should exist
    def self.instance
      first_or_create!
    end

    # Check if API keys are configured
    def openai_configured?
      openai_api_key.present?
    end

    def anthropic_configured?
      anthropic_api_key.present?
    end

    private

    def retain_existing_api_keys_when_blank
      API_KEY_ATTRIBUTES.each do |attribute|
        value = send(attribute)
        next unless value.is_a?(String) && value.blank?

        # Always normalize to the stored value - `nil` when this provider has
        # never had a key configured, or the previously-stored key otherwise.
        # A provider-never-configured + blank-submission combination must
        # persist as `nil`/NULL, not a literal encrypted empty string: a
        # persisted "" is `.present?` == false but still truthy, which lets it
        # short-circuit past `||`-chained credentials fallbacks (see
        # PromptEngine::OpenAiEvalsClient#initialize) that only trigger on a
        # falsy value.
        self[attribute] = attribute_in_database(attribute)
      end
    end
  end
end
