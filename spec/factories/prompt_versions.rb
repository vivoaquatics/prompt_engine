FactoryBot.define do
  factory :prompt_version, class: 'PromptEngine::PromptVersion' do
    association :prompt, factory: :prompt
    # version_number is automatically set by the model
    content { "Version content" }
    system_message { "You are a helpful assistant" }
    model { "gpt-4" }
    temperature { 0.7 }
    max_tokens { 1000 }
    metadata { {} }
    reasoning_effort { nil }
    created_by { "test_user" }
    change_description { "Test change" }

    trait :with_reasoning do
      model { "gpt-5.6-sol" }
      reasoning_effort { "high" }
    end
  end
end
